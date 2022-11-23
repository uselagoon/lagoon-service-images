# Logs dispatcher

Fluentd image with plugins required for use in the `lagoon-logging` chart.

# Development

Install [bundler](https://bundler.io/) locally.

## Updating Gemfile.lock

Check rubygems for newer gem versions that match the version constraints in Gemfile, and updates the Gemfile.lock with the results.

```
make update-gemfile
```

## Updating vendor/cache

Download the gems in Gemfile.lock to the local vendor/cache.

```
make update-vendor-cache
```

## Test build image

```
make build
```
