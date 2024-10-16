package images

import (
	"context"
	"log"

	"github.com/docker/docker/api/types/filters"
)

func (i *Images) PruneImagesCron() {
	_, err := i.Cron.AddFunc(i.PruneImageSchedule, func() {
		i.PruneImages(i.PruneImagesUntil)
	})

	if err != nil {
		log.Printf("Error initiating pruneImages cron: %v\n", err)
	}
}

func (i *Images) PruneDanglingImagesCron() {
	_, err := i.Cron.AddFunc(i.PruneDanglingImageSchedule, func() {
		i.PruneDanglingImages()
	})

	if err != nil {
		log.Printf("Error initiating pruneDanglingImages cron: %v\n", err)
	}
}

func (i *Images) PruneImages(until string) {
	log.Println("Starting image prune")
	ageFilter := filters.NewArgs()
	ageFilter.Add("until", until)

	// prune all images older than 7 days or what is specified in the environment variable
	pruneReport, err := i.Client.ImagesPrune(context.Background(), ageFilter)
	if err != nil {
		log.Println(err)
		return
	}
	log.Printf("Image prune complete: %d images deleted, %d bytes reclaimed\n",
		len(pruneReport.ImagesDeleted), pruneReport.SpaceReclaimed)
}

func (i *Images) PruneDanglingImages() {
	log.Println("Starting dangling image prune")
	pruneDanglingFilter := filters.NewArgs()
	pruneDanglingFilter.Add("dangling", "true")

	// Cleans up dangling images
	pruneReport, pruneErr := i.Client.ImagesPrune(context.Background(), pruneDanglingFilter)
	if pruneErr != nil {
		log.Println(pruneErr)
	}
	log.Printf("Dangling Image prune complete: %d images deleted, %d bytes reclaimed\n",
		len(pruneReport.ImagesDeleted), pruneReport.SpaceReclaimed)
}
