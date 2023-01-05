# Logs Concentrator

Fluentd image with plugins required for use in the `lagoon-logs-concentrator` chart.

# Development

Install [bundler](https://bundler.io/) locally.

## Updating Gemfile.lock

Check rubygems for newer gem versions that match the version constraints in Gemfile, and updates the Gemfile.lock with the results.

```
make update-gemfile
```

## Test build image

```
make build
```
