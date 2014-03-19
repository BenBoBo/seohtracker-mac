===================
Seohtracker for Mac
===================

Seohtracker is a simple app `made by Electric Hands Software
<http://www.elhaso.es/seohtracker/index>`_ to help you store and monitor your
weight. The app is open source and partially implemented with the `Nimrod
programming language <http://nimrod-lang.org>`_. The benefit of using Nimrod is
that `the core/business logic is separate and cross platform
<https://github.com/gradha/seohtracker-logic>`_, and being implemented it a
superior programming language makes it more fun to develop.  See
http://www.elhaso.es/seohtracker/index for the official web page.

Seohtracker is approved and in the Mac App store. You can go to
https://itunes.apple.com/es/app/seohtracker/id833683888?mt=12 to download the
app for free. You can also try `the iOS Seohtracker client
<https://github.com/gradha/seohtracker-ios>`_.


License
=======

`MIT license <LICENSE.rst>`_.


Building the app
================

To obtain the repository you need to request recursive submodules::

    $ git clone --recursive https://github.com/gradha/seohtracker-mac.git

Later, if you want to update you need to make sure modules get updated too::

    $ cd seohtracker-mac
    $ git pull
    $ git submodule update

In order to build the app you need a MacOSX machine with `Xcode
<https://itunes.apple.com/es/app/xcode/id497799835?mt=12>`_. Then you need to
install the `Nimrod compiler <http://nimrod-lang.org>`_. The stable version
0.9.2 of Nimrod may not work, try the git version if it fails to compile
something. All release issues annotate which compiler version was used (e.g.
https://github.com/gradha/seohtracker-mac/issues/25). Finally, install `nake
<https://github.com/fowlmouth/nake>`_, used to build parts of the project and
generate other necessary temporary files. It is recommended that you install
``nake`` through `the babel package manager
<https://github.com/nimrod-code/babel>`_.

Building the app should be as easy as opening the Xcode project, then selecting
one of the development or appstore targets and pressing the build or run
button. Unfortunately the build will likely fail, you still need to configure
some options in the `scripts/nimbuild.sh file <scripts/nimbuild.sh>`_ to let
the build know where to find the Nimrod compiler or the nake tool. The defaults
work for me, but you will need to create a ``scripts/nimbuild_options.sh`` file
to override some of the paths.

But once that's configured, everything should build and run. If not, tell me.

Documentation
=============

The app features some embedded documentation. You can see all of the static
files referenced from the `docindex.rst file <docindex.rst>`_. However you will
need to run ``nake doc`` to generate some of it, like the Mac specific help
files.


Changes
=======

This is development version v4.1. For a brief list of changes see the
`resources/html/appstore_changes.rst file
<resources/html/appstore_changes.rst>`_. For a detailed list of changes see the
`resources/html/full_changes.rst file <resources/html/full_changes.rst>`_.


Git branches
============

This project uses the `git-flow branching model
<https://github.com/nvie/gitflow>`_ with reversed defaults. Stable releases are
tracked in the ``stable`` branch. Development happens in the default ``master``
branch.


Feedback
========

You can send me feedback through `github's issue tracker
<https://github.com/gradha/seohtracker-mac/issues>`_. I also take a look from
time to time to `Nimrod's forums <http://forum.nimrod-code.org>`_ where you can
talk to other nimrod programmers.
