package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
	machineryvars "github.com/uselagoon/machinery/utils/variables"
)

const EnvOverrideHost = "DOCKER_HOST"

var dockerHost = machineryvars.GetEnv("DOCKER_HOST", "docker-host")
var repo = machineryvars.GetEnv("REPOSITORY_TO_UPDATE", "amazeeio")
var REGISTRY = machineryvars.GetEnv("REGISTRY", "docker-registry.default.svc:5000")
var BIP = machineryvars.GetEnv("BIP", "172.16.0.1/16")
var REGISTRY_MIRROR = machineryvars.GetEnv("REGISTRY_MIRROR", "https://imagecache.amazeeio.cloud")
var pruneImagesSchedule = machineryvars.GetEnv("PRUNE_SCHEDULE", "22 1 * * *")
var removeExitedSchedule = machineryvars.GetEnv("REMOVE_EXITED_SCHEDULE", "22 */4 * * *")
var updateImagesSchedule = machineryvars.GetEnv("UPDATE_IMAGES_SCHEDULE", "*/15 * * * *")
var pruneImagesUntil = machineryvars.GetEnv("PRUNE_IMAGES_UNTIL", "168h")
var danglingFilter = machineryvars.GetEnv("DANGLING_FILTER", "true")

func main() {
	cli, err := client.NewClientWithOpts(
		client.WithHostFromEnv(),
		client.WithAPIVersionNegotiation(),
	)
	if err != nil {
		fmt.Println("Error", err)
	}
	defer cli.Close()

	var command = fmt.Sprintf("/usr/local/bin/dind /usr/local/bin/dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --insecure-registry=%s --insecure-registry=harbor-harbor-core.harbor.svc.cluster.local:80 --bip=%s --storage-driver=overlay2 --storage-opt=overlay2.override_kernel_check=1 --registry-mirror=%s", REGISTRY, BIP, REGISTRY_MIRROR)
	var cmd = exec.Command("sh", "-c", command)

	if dockerHost != cli.DaemonHost() {
		fmt.Sprintf("Could not connect to %s", dockerHost)
	}
	c := cron.New()
	pruneImages(cli, c)
	removeExited(cli, c)
	updateImages(cli, c)
	c.Start()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("could not run command: ", err)
	}
}

func pruneImages(client *client.Client, c *cron.Cron) {
	c.AddFunc(pruneImagesSchedule, func() {
		log.Println("Starting image prune")
		ageFilter := filters.NewArgs()
		pruneDanglingFilter := filters.NewArgs()
		ageFilter.Add("until", pruneImagesUntil)
		pruneDanglingFilter.Add("dangling", danglingFilter)

		// # prune all images older than 7 days or what is specified in the environment variable
		_, err := client.ImagesPrune(context.Background(), ageFilter)
		if err != nil {
			log.Println(err)
		}
		// # prune all docker build cache images older than 7 days or what is specified in the environment variable
		_, buildErr := client.BuildCachePrune(context.Background(), types.BuildCachePruneOptions{Filters: ageFilter})
		if buildErr != nil {
			log.Println(buildErr)
		}
		// # after old images are pruned, clean up dangling images
		_, pruneErr := client.ImagesPrune(context.Background(), pruneDanglingFilter)
		if pruneErr != nil {
			log.Println(pruneErr)
		}
		log.Println("Prune complete")
	})
}

func removeExited(client *client.Client, c *cron.Cron) {
	c.AddFunc(removeExitedSchedule, func() {
		log.Println("Starting removeExited")
		ctx := context.Background()
		statusFilter := filters.NewArgs()
		statusFilter.Add("status", "exited")
		containers, err := client.ContainerList(ctx, types.ContainerListOptions{
			Filters: statusFilter,
		})
		if err != nil {
			log.Println(err)
		}

		// # remove all exited containers
		for _, container := range containers {
			err := client.ContainerRemove(ctx, container.ID, types.ContainerRemoveOptions{
				Force:         true,
				RemoveVolumes: true,
			})
			if err != nil {
				log.Println(err)
			}
		}
		log.Println("removeExited complete")
	})
}

func updateImages(client *client.Client, c *cron.Cron) {
	c.AddFunc(updateImagesSchedule, func() {
		log.Println("Starting update images")
		ctx := context.Background()
		filters := filters.NewArgs()
		filters.Add("reference", fmt.Sprintf("%s/*:*", repo))
		images, err := client.ImageList(ctx, types.ImageListOptions{Filters: filters})
		if err != nil {
			log.Println(err)
		}

		var imgRepoTags []string
		for _, img := range images {
			imgRepoTags = append(imgRepoTags, img.RepoTags...)
		}

		// # Iterates through all images that have the name of the repository we are interested in in it
		for _, image := range imgRepoTags {
			out, err := client.ImagePull(ctx, image, types.ImagePullOptions{})
			if err != nil {
				log.Println(err)
			}
			defer out.Close()
			io.Copy(os.Stdout, out)
		}
		log.Println("Update images complete")
	})
}
