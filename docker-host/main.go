package main

import (
	"context"
	"fmt"
	"io"
	"os"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
)

const EnvOverrideHost = "DOCKER_HOST"

var dockerHost = os.Getenv("DOCKER_HOST")
var repo = getEnv("REPOSITORY_TO_UPDATE", "amazeeio")

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

	pruneImages(cli)
	removeExited(cli)
	updateImages(cli)
}

func pruneImages(client *client.Client) {
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
}

func removeExited(client *client.Client) {
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
}

func updateImages(client *client.Client) {
	ctx := context.Background()
	filters := filters.NewArgs()
	filters.Add("reference", fmt.Sprintf("%s/*:*", repo))
	images, err := client.ImageList(ctx, types.ImageListOptions{Filters: filters})
	if err != nil {
		panic(err)
	}

	// # Iterates through all images that have the name of the repository we are interested in in it
	for i, image := range images {
		out, err := client.ImagePull(ctx, image.RepoTags[i], types.ImagePullOptions{})
		if err != nil {
			panic(err)
		}
		defer out.Close()
		io.Copy(os.Stdout, out)
	}
	fmt.Println("Update images complete")
}

// #Todo
// func updatePushImages(client *client.Client) {
// }

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if len(value) == 0 {
		return defaultValue
	}
	return value
}
