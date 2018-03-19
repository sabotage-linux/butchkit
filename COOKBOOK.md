### Butch, the build manager

`butch` is a collection of small shell scripts, living in `KEEP/bin` of this
repo and is usually also installed into /bin of a sabotage system.
it was originally written in C for speed, but was recently replaced with a
pure POSIX shell implementation (the performance-sensitive parts are outsourced
into awk scripts, so at least on an average-speed CPU there's no notable
difference. It's probably slightly slower now on low-end ARM and MIPS CPUs).

It handles package downloads, checksums, builds and dependencies in a
relatively sane manner.
Parallel downloads are automatically enabled if a `jobflow` binary is present
on the system (default on a sabotage install).

To see a list of supported commands, execute `butch` without arguments.

`butch` will by default start sixteen download jobs and one build job.
You can influence the number of download jobs with the `BUTCH_DL_THREADS`
environment variable.
If you're behind a super-fast gigabit link, it may make sense to increase this
number considerably, for example to `64`.
If your connection is very poor, you may want to set it to only `1`-`4`.
To make the setting persistent, put it into your `config`.
The previous C version of butch used to support multiple build jobs as well,
however that turned out to be very confusing since it was not possible to tell
which package is currently building and we achieve parallel CPU usage anyway
using the `MAKE_THREADS` variable (see section `Variables` for details).

By default, `butch` uses the system's `wget`.
To enable HTTPS support install the `stage2` package, which adds `libressl`
and `ca-certificates` to the system.
You may also use `curl` by exporting `USE_CURL=1`. For best results, download
all packages before the install process.

`butch` defaults to installing built packages into `/opt/$packagename`. Files
are then symlinked into a user-definable path, defaulting to `/`. Finally, the
package name and `pkgver` of its recipe are then written to `/var/lib/butch.db`.

The `/opt` path can be overridden by adding the variable `butch_staging_dir` to
the config file and setting it to the desired value. It must consist of a single
component, for example `/foo` `/app` or `/Packages`. The staging dir will
always be used inside the filesystem root specified in the used config.

`butch` may also be used for system configuration, eschewing the package
building features by simply calling `exit 0` at the conclusion of a package
recipe. This will avoid the above package installation procedure.

To completely remove a package:

	$ rm -rf /opt/$pkg
	$ butch unlink $pkg
	$ sed -i '/$pkg/d' /var/lib/butch.db # ... or edit by hand.


### /src, the heart of the system

`/src` is the default path where `butch` searches for and builds packages.

	/src
	/src/pkg        # package recipes, used by butch
	/src/KEEP       # patches and other files referenced from scripts
	/src/build      # package build directory. Safe to empty from time to time
	/src/filelists  # per-package file lists, referenced by `butch unlink`
	/src/logs       # per-package download and build logs
	/src/tarballs   # upstream package tarballs
	/src/utils      # sabotage utilities and helper scripts

`butch` requires `/src/pkg`,`/src/KEEP` and `/src/config`. It will fail to
start if they are missing. The rest of this directory is optional with caveats.

Erasing `/src/filelists` will break `butch unlink <package>` for existing
packages.

`find . -type f -or -type l > /src/filelists/$packagename.txt` from
the installation directory recovers the list.

Erasing `/src/utils` will lose scripts for cross-compilation, writing recipes,
managing chroots and other functionality. Each script contains brief
documentation explaining usage.

There is no issue erasing `/src/tarballs`, `/src/logs` or `/src/build` beyond
the obvious.

It is suggested to clone the upstream repo as `/src/sabotage`:

	$ git clone git://github.com/sabotage-linux/sabotage /src/sabotage
	$ rm -rf /src/KEEP /src/pkg
	$ ln -sf /src/sabotage/KEEP /src/KEEP
	$ ln -sf /src/sabotage/pkg /src/pkg

You can issue a `git pull` in `/src/sabotage` to update to the latest version of
recipes and utilities.


### Writing recipes


	[mirrors]
	[vars]
	[deps]
	[build]

`butch` recipes are plain text files that contain one or more labeled headers
and their associated data. The above four sections are central to an assortment
of different possible recipes. This section details their use.

	[mirrors]
	<url #1>
	...
	<url #n>

	[vars]
	filesize=<bytes>
	sha512=<sha 512 hash>
	tardir=<directory name the tar extracts to, if it differs from the tar name>
	tarball=<optionally specified, if needed>
	pkgver=<package revision>

`[mirrors]` and `[vars]` are optional, but must be included together as a set.
HTTP(S) is the only valid protocol for `[mirrors]`. `tardir` and `tarball` are
optional directives and are usually omitted.

The `[vars]` section is copied verbatim to the top of these generated scripts and
may contain shell code.

The `utils/dlinfo` script is useful in generating the above sections for you.

	[deps]
	<package #1>
	...
	<package #n>

	[deps.host]
	<package #1>
	...
	<package #n>

	[deps.run]
	<package #1>
	...
	<package #n>

Any combination of the above three headers may optionally be present.

`[deps]` is the standard list of dependencies required by the recipe.
`[deps.host]` are dependencies required on the host for cross-compilation.
`[deps.run]` are requirements to run the package on the target system.

	[build]
	<shell instructions to build application>

Shell instructions inside [build] will be performed by butch during
compilation. Specifying `butch_do_relocate=false` inside `[build]` will
prevent the post-build linking of files. If the`[build]` phase calls `exit`,
`butch` will not perform any post-build activities at all.

These recipe elements combine with `KEEP/butch_download_template.txt` as a
`build/dl_package.sh` script. They also join
`KEEP/butch_template_configure_cached.txt` to form `build/build_package.sh`.

Metapackages containing only a `[mirrors]` & `[vars]`, `[deps]` or `[build]`
section are useful.


### Variables and Templates

Sabotage provides environment variables used for scripts and recipes, sourced
from `/src/config`. This section describes them in detail.

The `stage1` values are provided here, along with a brief description of the variable.

        SABOTAGE_BUILDDIR="/tmp/sabotage"

Defines where the `./build-stage0` script builds a chroot.

	A=x86_64

Selects an architecture to build for. 'i386', 'arm', 'mips' and 'powerpc' are
other options.

	CC=gcc
	HOSTCC=gcc

The C compiler used. `gcc` is currently the only compiler tested and supported.

	MAKE_THREADS=1

The number of threads to pass to make via the -j flag.

        BUTCH_BIN="/a/path/to/butch-core"

If not set, `./build-stage0` will download and build `butch`. On systems lacking a
proper libc, you may need to statically build `butch` yourself then specify it with
this variable.

	R=/               # `R` is the system root that butch will link packages into
	S=/src            # `S` is the source directory for `butch`
	K=/src/KEEP       # `K` is a directory of needed files and patches
	C=/src/tarballs   # `C` is the downloaded tarball cache
	LOGPATH=/src/logs # `LOGPATH` is where everything is logged

Internal paths, useful when writing scripts and recipes. You should leave these
all as-is, this is the intended way.

	BUTCH_BUILD_TEMPLATE="$K"/butch_template_configure_cached.txt

The build template. It creates packages in `$R/opt/$package_name` and
optionally supplies a `config.cache` file to speed up some from-source
compilation recipes. Review the template to see its configurable options.

	BUTCH_DOWNLOAD_TEMPLATE="$K"/butch_download_template.txt

The download template. It downloads, tests and unpacks tarballs.

        STAGE=1

Used during the bootstrap process by scripts to determine the current stage.
Leave this alone.

