package images

import (
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
)

type Images struct {
	Client                     *client.Client
	Cron                       *cron.Cron
	UpdateSchedule             string
	Repositories               string
	PruneImageSchedule         string
	PruneImagesUntil           string
	PruneDanglingImageSchedule string
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
