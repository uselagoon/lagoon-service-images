package containers

import (
	"context"
	"log"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
)

type Containers struct {
	Client               *client.Client
	Cron                 *cron.Cron
	RemoveExitedSchedule string
}

func (c *Containers) RemoveExitedCron() {
	_, err := c.Cron.AddFunc(c.RemoveExitedSchedule, func() {
		c.RemoveExited()
	})

	if err != nil {
		log.Printf("Error initiating removeExited cron: %v\n", err)
	}
}

func (c *Containers) RemoveExited() {
	log.Println("Starting removeExited")
	ctx := context.Background()
	statusFilter := filters.NewArgs()
	statusFilter.Add("status", "paused")
	statusFilter.Add("status", "exited")
	statusFilter.Add("status", "dead")
	statusFilter.Add("status", "created")
	containers, err := c.Client.ContainerList(ctx, container.ListOptions{
		Filters: statusFilter,
	})
	if err != nil {
		log.Println(err)
		return
	}

	// remove all exited containers
	for _, con := range containers {
		err := c.Client.ContainerRemove(ctx, con.ID, container.RemoveOptions{
			Force:         true,
			RemoveVolumes: true,
		})
		if err != nil {
			log.Println(err)
		}
	}
	log.Println("removeExited complete")
}
