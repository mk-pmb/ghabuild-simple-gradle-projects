
<!--#echo json="package.json" key="name" underline="=" -->
ghabuild-simple-gradle-projects
===============================
<!--/#echo -->

<!--#echo json="package.json" key="description" -->
Because too many projects lack their own GitHub Actions workflows for
building.
<!--/#echo -->


Motivation
----------

You want to build a gradle project but…

  * … don't want to install Java or gradle on your dev computer.
  * … don't want to invest your own RAM, disk space, time.
  * … want to show a result or an error message in a way that's easy to
    reproduce for others, independent of your computer's settings.

That's where GitHub Actions can help. Just build it in the cloud!

However, some projects don't make it very easy to start a cloud build
for your specific branch, or just any branch you want to try.

That's where this project can help. At least in simple cases.



How to use
----------

see [docs/README.md](docs/README.md).


<!--#toc stop="scan" -->



Known issues
------------

* Needs more/better tests and docs.




&nbsp;


License
-------

The files in this actual repo are multi-licensed as `ISC`,
`MIT` and `LGPL-3.0-only`. Choose any combination you like.

#### ⚠ The workflows ⚠

… may fetches files governed by other licenses,
so the artifacts built often are under a different license,
usually the one of the project being imported.
