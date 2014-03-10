====================================
What to do for a new public release?
====================================

* Create new milestone with version number.
* Create new dummy issue `Release versionname` and assign to that milestone.
* Annotate the release issue with the Nimrod commit used to compile sources,
  and Xcode version too.
* git flow release start versionname (versionname without v).
* Update version numbers:

  * Modify `README.rst <../README.rst>`_ (s/development/stable/).
  * Make sure `resources/plist/appstore-Info.plist
    <../resources/plist/appstore-Info.plist>`_ lists new version
    number. Short version is visible to appstore, version is kind
    of internal.
  * Make sure `resources/plist/devel-Info.plist
    <../resources/plist/devel-Info.plist>`_ lists new version number.
  * Modify `resources/html/appstore_changes.rst
    <../resources/html/appstore_changes.rst>`_ with list of changes and
    version/number.
  * Modify `resources/html/full_changes.rst
    <../resources/html/full_changes.rst>`_ with list of changes and
    version/number.

* ``git commit -av`` into the release branch the version number changes.
* Verify if files in ``resources/screenshots`` need updating.
* Save ``build/google_analytics_config.h``, trash ``build`` directory and
  recover the header file.
* Now build an archive of the appstore target and upload to iTunes connect.
* Remove again ``build/google_analytics_config.h``, zip up ``build`` directory
  as ``build-sources-XXX.zip`` and keep somewhere.
* ``git flow release finish versionname`` (the tagname is versionname without
  ``v``).  When specifying the tag message, copy and paste a text version of
  the full changes log into the message. Add rst item markers.
* Move closed issues to the release milestone.
* Increase version numbers, ``master`` branch gets +0.1.

  * Modify `README.rst <../README.rst>`_.
  * Modify `resources/plist/appstore-Info.plist
    <../resources/plist/appstore-Info.plist>`_.
  * Modify `resources/plist/devel-Info.plist
    <../resources/plist/devel-Info.plist>`_.
  * Add to `resources/html/appstore_changes.rst
    <../resources/html/appstore_changes.rst>`_ development version with unknown
    date.
  * Add to `resources/html/full_changes.rst
    <../resources/html/full_changes.rst>`_ development version with unknown
    date.

* ``git commit -av`` into ``master`` with *Bumps version numbers for
  development version. Refs #release issue*.
* ``git push origin master stable --tags``.
* Close the dummy release issue.

----

* Patiently wait until Apple approves the binary on the appstore.
* Update if necessary http://www.elhaso.es/seohtracker/index.
* Announce at http://forum.nimrod-lang.org/.
* Close the milestone on github.
* Update the released tag on https://github.com/gradha/seohtracker-mac/releases
  with the template message **"Available on the mac appstore on YYYY-MM-DD"**.
  Attach previously saved ``build-sources-XXX.zip``.
