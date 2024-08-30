package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
	machineryvars "github.com/uselagoon/machinery/utils/variables"
)

const EnvOverrideHost = "DOCKER_HOST"

var dockerHost = machineryvars.GetEnv("DOCKER_HOST", "docker-host")
var repositoriesToUpdate = machineryvars.GetEnv("REPOSITORIES_TO_UPDATE", "uselagoon")
var REGISTRY = machineryvars.GetEnv("REGISTRY", "docker-registry.default.svc:5000")
var BIP = machineryvars.GetEnv("BIP", "172.16.0.1/16")
var logLevel = machineryvars.GetEnv("LOG_LEVEL", "info")
var REGISTRY_MIRROR = machineryvars.GetEnv("REGISTRY_MIRROR", "")
var pruneImagesSchedule = machineryvars.GetEnv("PRUNE_SCHEDULE", "22 1 * * *")
var pruneDanglingSchedule = machineryvars.GetEnv("PRUNE_DANGLING_SCHEDULE", "22 1 * * *")
var removeExitedSchedule = machineryvars.GetEnv("REMOVE_EXITED_SCHEDULE", "22 */4 * * *")
var updateImagesSchedule = machineryvars.GetEnv("UPDATE_IMAGES_SCHEDULE", "*/15 * * * *")
var pruneImagesUntil = machineryvars.GetEnv("PRUNE_IMAGES_UNTIL", "168h")

func main() {
	cli, err := client.NewClientWithOpts(
		client.WithHostFromEnv(),
		client.WithAPIVersionNegotiation(),
	)
	if err != nil {
		log.Fatalf("Error: %v", err)
	}
	defer cli.Close()

	var command = fmt.Sprintf("/usr/local/bin/dind /usr/local/bin/dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --bip=%s --storage-driver=overlay2 --tls=false --log-level=%s", BIP, logLevel)
	if REGISTRY != "" {
		command = command + fmt.Sprintf(" --insecure-registry=%s", REGISTRY)
	}
	if REGISTRY_MIRROR != "" {
		command = command + fmt.Sprintf(" --registry-mirror=%s", REGISTRY_MIRROR)
	}
	var cmd = exec.Command("sh", "-c", command)

	if dockerHost != cli.DaemonHost() {
		log.Fatalf("Could not connect to %s", dockerHost)
	}
	c := cron.New()
	pruneImages(cli, c)
	pruneDanglingImages(cli, c)
	removeExited(cli, c)
	updateImages(cli, c)
	c.Start()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		log.Fatalf("could not run command: %v", err)
	}
}

func pruneImages(client *client.Client, c *cron.Cron) {
	_, err := c.AddFunc(pruneImagesSchedule, func() {
		log.Println("Starting image prune")
		ageFilter := filters.NewArgs()
		ageFilter.Add("until", pruneImagesUntil)

		// prune all images older than 7 days or what is specified in the environment variable
		pruneReport, err := client.ImagesPrune(context.Background(), ageFilter)
		if err != nil {
			log.Println(err)
			return
		}
		// prune all docker build cache images older than 7 days or what is specified in the environment variable
		_, buildErr := client.BuildCachePrune(context.Background(), types.BuildCachePruneOptions{Filters: ageFilter})
		if buildErr != nil {
			log.Println(buildErr)
		}
		log.Printf("Image prune complete: %d images deleted, %d bytes reclaimed\n",
			len(pruneReport.ImagesDeleted), pruneReport.SpaceReclaimed)
	})

	if err != nil {
		log.Printf("Error initiating pruneImages cron: %v\n", err)
	}
}

func pruneDanglingImages(client *client.Client, c *cron.Cron) {
	_, err := c.AddFunc(pruneDanglingSchedule, func() {
		log.Println("Starting dangling image prune")
		pruneDanglingFilter := filters.NewArgs()
		pruneDanglingFilter.Add("dangling", "true")

		// Cleans up dangling images
		pruneReport, pruneErr := client.ImagesPrune(context.Background(), pruneDanglingFilter)
		if pruneErr != nil {
			log.Println(pruneErr)
		}
		log.Printf("Dangling Image prune complete: %d images deleted, %d bytes reclaimed\n",
			len(pruneReport.ImagesDeleted), pruneReport.SpaceReclaimed)
	})

	if err != nil {
		log.Printf("Error initiating pruneDanglingImages cron: %v\n", err)
	}
}

func removeExited(client *client.Client, c *cron.Cron) {
	_, err := c.AddFunc(removeExitedSchedule, func() {
		log.Println("Starting removeExited")
		ctx := context.Background()
		statusFilter := filters.NewArgs()
		statusFilter.Add("status", "exited")
		containers, err := client.ContainerList(ctx, container.ListOptions{
			Filters: statusFilter,
		})
		if err != nil {
			log.Println(err)
			return
		}

		// remove all exited containers
		for _, con := range containers {
			err := client.ContainerRemove(ctx, con.ID, container.RemoveOptions{
				Force:         true,
				RemoveVolumes: true,
			})
			if err != nil {
				log.Println(err)
			}
		}
		log.Println("removeExited complete")
	})

	if err != nil {
		log.Printf("Error initiating removeExited cron: %v\n", err)
	}
}

func updateImages(client *client.Client, c *cron.Cron) {
	_, err := c.AddFunc(updateImagesSchedule, func() {
		log.Println("Starting update images")
		ctx := context.Background()
		ImgFilters := addFilters(repositoriesToUpdate)
		preUpdateImages, err := client.ImageList(ctx, image.ListOptions{Filters: ImgFilters})
		if err != nil {
			log.Println(err)
			return
		}

		var preUpdateIDs []string
		for _, img := range preUpdateImages {
			preUpdateIDs = append(preUpdateIDs, img.ID)
		}

		var imgRepoTags []string
		for _, img := range preUpdateImages {
			if img.RepoTags != nil {
				imgRepoTags = append(imgRepoTags, img.RepoTags...)
			}
		}

		// Iterates through all images that have the name of the repository we are interested in it
		for _, img := range imgRepoTags {
			out, err := client.ImagePull(ctx, img, image.PullOptions{})

			if err != nil {
				log.Println(err)
				continue
			}
			defer out.Close()
			_, error := io.Copy(io.Discard, out)
			if error != nil {
				log.Println(err)
			}
		}

		postUpdateImages, err := client.ImageList(ctx, image.ListOptions{Filters: ImgFilters})
		if err != nil {
			log.Println(err)
		}

		var postUpdateIDs []string
		for _, img := range postUpdateImages {
			postUpdateIDs = append(postUpdateIDs, img.ID)
		}

		updatedImages := imgComparison(preUpdateIDs, postUpdateIDs)
		for _, img := range postUpdateImages {
			for _, updatedImg := range updatedImages {
				if img.ID == updatedImg {
					log.Println(fmt.Sprintf("Updated image %s", img.RepoTags))
				}
			}
		}

		imgPluralize := ""
		if len(updatedImages) == 1 {
			imgPluralize = "image"
		} else {
			imgPluralize = "images"
		}
		log.Println(fmt.Sprintf("Update images complete | %d %s updated", len(updatedImages), imgPluralize))
	})

	if err != nil {
		log.Printf("Error initiating updateImages cron: %v\n", err)
	}
}

func imgComparison(preUpdate, postUpdate []string) []string {
	var updatedImgs []string

	for i := 0; i < 2; i++ {
		for _, preUpdateImg := range preUpdate {
			found := false
			for _, postUpdateImg := range postUpdate {
				if preUpdateImg == postUpdateImg {
					found = true
					break
				}
			}
			if !found {
				updatedImgs = append(updatedImgs, preUpdateImg)
			}
		}
		if i == 0 {
			preUpdate, postUpdate = postUpdate, preUpdate
		}
	}
	return updatedImgs
}

func addFilters(repo string) filters.Args {
	repoFilters := filters.NewArgs()
	splitRepos := strings.Split(repo, "|")
	for _, repo := range splitRepos {
		repoFilters.Add("reference", repo)
	}
	return repoFilters
}
