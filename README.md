
# pyenv-pyqt-build

pyenv-pyqt-build is a [pyenv](https://github.com/pyenv/pyenv) plugin that
provides commands to install and manage PyQt installation across multiple pyenv
versions.

## Installing

The pyenv-pyqt-build pyenv plugin can be installed with the following steps:
```
$ cd $(pyenv root)/plugins
$ git clone https://github.com/sprout42/pyenv-pyqt-build/
```

## Usage

An existing QT installation is required to successfully install PyQt. This can
be accomplished in any normal way supported on your platform.

### Example
This example uses [homebrew](https://brew.sh/) to handle the QT installation.
To install the latest opensource licensed QT5 and PyQt5 in a python 2.7.18
environment created by pyenv:
```
$ brew install qt@5
$ pyenv install 2.7.18
$ PYENV_VERSION=2.7.18 pyenv pyqt5 install
```

These utilities have been tested using the official homebrew QT5 installation,
alternate QT4 solutions such as
[https://github.com/cartr/homebrew-qt4](https://github.com/cartr/homebrew-qt4)
should also work for installing PyQt4 but have not yet been tested.

There are 3 primary commands provided by this plugin:
- `pyqt5`
- `pyqt4`
- `sip`

## Commands

### `pyenv <command> versions`

Lists the available versions that can be installed. The available versions are
collected from [pypi](https://pypi.org/),
[Sourceforge](https://sourceforge.net/projects/pyqt/files/), and
[Mercurial](https://www.riverbankcomputing.com/hg/sip) depending on the package
that information is being requested for. Because this information is collected 
from the internet and shouldn't change too often the available versions are 
cached and future calls ot `pyenv <command> versions` will re-use this cached 
version information.

The version cache can be updated with the `pyenv <command> update` command.

### `pyenv <command> install [version]`

Installs the requested package through `pip` or by manually building the source.
None of the dependencies required to compile a package are installed by this
tool (except for `sip`) so additional dependencies may need to be installed
before compilation is successful.

When installing `PyQt5` or `PyQt4` the plugins attempt to discover the minimum
required version of `sip` to install and will do that automatically. Normally it
is not necessary to use the `pyenv sip` commands to install sip directly. When
the version to install is not provided The plugins attempt to discover the
correct version of PyQt to install by searching for the `qmake` executable in
the PATH, or if installed with `brew`. If a `qmake` executable can't be found it
must be provided using the `--qmake` argument:
```
$ pyenv install pyqt5 --qmake=/opt/QT/bin/qmake
```

The plugin will try to use install the desired package through `pip` whenever
possible, but will also use the official source releases or mercurial source
(for sip only) as needed.

### `pyenv <command> show [version]`

Displays the package version installed, and the version as reported through the 
python API.
