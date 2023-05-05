
How to build a simple gradle project
====================================

1.  In a new (or existing) Git repository, make a new branch…
    * … whose name starts with `build-` or `debug-`
    * … that has a copy of the [example `job.rc`](job.rc)
    * … and, in subdirectory `.github/workflows/`,
      has the [`ignite.yaml`](ignite.yaml).
1.  Edit `job.rc` according to the hints inside.
1.  Optionally, if you want to try a more recent (but potentially broken)
    version of the build scripts, edit `ignite.yaml` to set another
    branch name (e.g. `experimental`) at the end of the `uses:` line.
1.  Commit your changes and push your branch to GitHub.
1.  The GitHub Actions tab should pick up the push within a few seconds,
    and should start building.
1.  If the project is simple enough, the build will actually succeed,
    probably within a few minutes.

For inspiration, have a look at the `build-…` branches of this repository.



