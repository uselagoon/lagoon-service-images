# Insights-Remote Trivy

This image simply extends the standard Trivy docker image to include the vulnerability databases,
rather than downloading them every time it is invoked.

It results in a bigger image, but the way Insights scans work often require the _entire_ DB to be downloaded
every time it is run (which is multiple times a build).

