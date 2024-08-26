package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
)

const EnvOverrideHost = "DOCKER_HOST"

var dockerHost = os.Getenv("DOCKER_HOST")
var repo = getEnv("REPOSITORY_TO_UPDATE", "amazeeio")
var REGISTRY = getEnv("REGISTRY", "docker-registry.default.svc:5000")
var BIP = getEnv("BIP", "172.16.0.1/16")
var REGISTRY_MIRROR = getEnv("REGISTRY_MIRROR", "https://imagecache.amazeeio.cloud")

func main() {
	cli, err := client.NewClientWithOpts(
		client.WithHostFromEnv(),
	)
	if err != nil {
		fmt.Println("Error", err)
	}
	defer cli.Close()

	if cli.DaemonHost() != dockerHost {
		fmt.Sprintf("Could not connect to %s", dockerHost)
	}
	var command = fmt.Sprintf("/usr/local/bin/dind /usr/local/bin/dockerd --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --insecure-registry=%s --insecure-registry=harbor-harbor-core.harbor.svc.cluster.local:80 --bip=%s --storage-driver=overlay2 --storage-opt=overlay2.override_kernel_check=1 --registry-mirror=%s", REGISTRY, BIP, REGISTRY_MIRROR)
	c := cron.New()
	pruneImages(cli, c)
	removeExited(cli, c)
	updateImages(cli, c)
	c.Start()
	cmd := exec.Command("sh", "-c", command)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("could not run command: ", err)
	}
}

func pruneImages(client *client.Client, c *cron.Cron) {
	c.AddFunc("22 1 * * *", func() {
		ageFilter := filters.NewArgs()
		danglingFilter := filters.NewArgs()
		ageFilter.Add("until", "168")
		danglingFilter.Add("dangling", "true")

		// # prune all images older than 7 days or what is specified in the environment variable
		client.ImagesPrune(context.Background(), ageFilter)

		// # prune all docker build cache images older than 7 days or what is specified in the environment variable
		client.BuildCachePrune(context.Background(), types.BuildCachePruneOptions{Filters: ageFilter})

		// # after old images are pruned, clean up dangling images
		client.ImagesPrune(context.Background(), danglingFilter)

		fmt.Println("Prune complete")
	})
}

func removeExited(client *client.Client, c *cron.Cron) {
	c.AddFunc("22 */4 * * *", func() {
		ctx := context.Background()
		statusFilter := filters.NewArgs()
		statusFilter.Add("status", "exited")
		containers, err := client.ContainerList(ctx, types.ContainerListOptions{
			Filters: statusFilter,
		})
		if err != nil {
			panic(err)
		}

		// # remove all exited containers
		for _, container := range containers {
			_ = client.ContainerRemove(ctx, container.ID, types.ContainerRemoveOptions{
				Force:         true,
				RemoveVolumes: true,
			})
		}

		fmt.Println("removeExited complete")
	})
}

func updateImages(client *client.Client, c *cron.Cron) {
	c.AddFunc("*/15 * * * *", func() {
		ctx := context.Background()
		filters := filters.NewArgs()
		filters.Add("reference", fmt.Sprintf("%s/*:*", repo))
		images, err := client.ImageList(ctx, types.ImageListOptions{Filters: filters})
		if err != nil {
			panic(err)
		}

		var imgRepoTags []string
		for _, img := range images {
			imgRepoTags = append(imgRepoTags, img.RepoTags...)
		}

		// # Iterates through all images that have the name of the repository we are interested in in it
		for _, image := range imgRepoTags {
			out, err := client.ImagePull(ctx, image, types.ImagePullOptions{})
			if err != nil {
				panic(err)
			}
			defer out.Close()
			io.Copy(os.Stdout, out)
		}
		fmt.Println("Update images complete")
	})
}

// func updatePushImages(client *client.Client) {
// 	ctx := context.Background()
// 	namespace, err := ioutil.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
// 	if err != nil {
// 		fmt.Println(fmt.Sprintf("Task failed to read the token, error was: %v", err))
// 		os.Exit(1)
// 	}
// 	token, err := ioutil.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/token")
// 	if err != nil {
// 		fmt.Println(fmt.Sprintf("Task failed to read the token, error was: %v", err))
// 		os.Exit(1)
// 	}
// 	client.RegistryLogin(ctx, types.AuthConfig{
// 		Username:      "serviceaccount",
// 		Password:      "",
// 		RegistryToken: fmt.Sprintf("%s:%s", registryHost, token),
// 	})

// 	filters := filters.NewArgs()
// 	filters.Add("reference", fmt.Sprintf("%s/*:*", repo))
// 	images, err := client.ImageList(ctx, types.ImageListOptions{Filters: filters})
// 	if err != nil {
// 		panic(err)
// 	}

// 	var imgRepoTags []string
// 	for _, img := range images {
// 		imgRepoTags = append(imgRepoTags, img.RepoTags...)
// 	}

// 	imageNoRespository := ""

// 	for _, fullImage := range imgRepoTags {
// 		image := strings.Split(fullImage, "/")

// 		if len(image) == 3 {
// 			imageNoRespository = image[2]
// 		} else {
// 			imageNoRespository = image[1]
// 		}

// 		// # pull newest version of found image
// 		out, err := client.ImagePull(ctx, fullImage, types.ImagePullOptions{})
// 		if err != nil {
// 			panic(err)
// 		}
// 		defer out.Close()

// 		// # Tag the image with the openshift registry name and the openshift project this container is running
// 		client.ImageTag(ctx, fullImage, fmt.Sprintf("%s/%s/%s", registryHost, namespace, imageNoRespository))

// 		// # Push to the openshift registry
// 		client.ImagePush(ctx, fmt.Sprintf("%s/%s/%s", registryHost, namespace, imageNoRespository), types.ImagePushOptions{})
// 	}
// }

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if len(value) == 0 {
		return defaultValue
	}
	return value
}
