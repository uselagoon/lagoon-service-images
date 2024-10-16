package cache

import (
	"context"
	"log"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
	"github.com/robfig/cron/v3"
)

type Cache struct {
	Client                    *client.Client
	Cron                      *cron.Cron
	PruneBuilderCacheSchedule string
	PruneBuilderCacheUntil    string
}

func (c *Cache) PruneBuilderCacheCron() {
	_, err := c.Cron.AddFunc(c.PruneBuilderCacheSchedule, func() {
		c.PruneBuilderCache(c.PruneBuilderCacheUntil)
	})

	if err != nil {
		log.Printf("Error initiating pruneBuilderCache cron: %v\n", err)
	}
}

func (c *Cache) PruneBuilderCache(until string) {
	_, err := c.Cron.AddFunc(c.PruneBuilderCacheSchedule, func() {
		log.Println("Starting builder cache prune")
		ageFilter := filters.NewArgs()
		ageFilter.Add("until", until)
		builderCacheOpts := types.BuildCachePruneOptions{
			Filters: ageFilter,
		}

		// Cleans up build cache images
		pruneReport, pruneErr := c.Client.BuildCachePrune(context.Background(), builderCacheOpts)
		if pruneErr != nil {
			log.Println(pruneErr)
		}
		log.Printf("Builder Cache prune complete: %d deleted, %d bytes reclaimed\n",
			len(pruneReport.CachesDeleted), pruneReport.SpaceReclaimed)
	})

	if err != nil {
		log.Printf("Error initiating pruneBuilderCache cron: %v\n", err)
	}
}
