package helpers

import (
	"strings"

	"github.com/docker/docker/api/types/filters"
)

func AddFilters(repo string) filters.Args {
	repoFilters := filters.NewArgs()
	splitRepos := strings.Split(repo, "|")
	for _, repo := range splitRepos {
		repoFilters.Add("reference", repo)
	}
	return repoFilters
}
