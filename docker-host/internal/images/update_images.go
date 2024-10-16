package images

import (
	"context"
	"io"
	"log"

	"github.com/docker/docker/api/types/image"
	"github.com/uselagoon/lagoon-service-images/docker-host/internal/helpers"
)

func (i *Images) UpdateImagesCron() {
	_, err := i.Cron.AddFunc(i.UpdateSchedule, func() {
		i.UpdateImages()
	})

	if err != nil {
		log.Printf("Error initiating updateImages cron: %v\n", err)
	}
}

func (i *Images) UpdateImages() {
	log.Println("Starting update images")
	ctx := context.Background()
	ImgFilters := helpers.AddFilters(i.Repositories)
	preUpdateImages, err := i.Client.ImageList(ctx, image.ListOptions{Filters: ImgFilters})
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
		out, err := i.Client.ImagePull(ctx, img, image.PullOptions{})

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

	postUpdateImages, err := i.Client.ImageList(ctx, image.ListOptions{Filters: ImgFilters})
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
				log.Printf("Updated image %s", img.RepoTags)
			}
		}
	}

	imgPluralize := ""
	if len(updatedImages) == 1 {
		imgPluralize = "image"
	} else {
		imgPluralize = "images"
	}
	log.Printf("Update images complete | %d %s updated", len(updatedImages), imgPluralize)
}
