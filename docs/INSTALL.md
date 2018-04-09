Installation
============

Quickie Installation
--------------------

1. Run `make install` while you are in the Lyve-SET directory. This step probably takes 10-20 minutes.
2. Update the path to include the scripts subdirectory. You can do this yourself if you are comfortable or run `make env`.
3. Update your current session's path: `source ~/.bashrc`

Requirements
------------
* **Must-have** and not installed with `make install`
  * **Perl, multithreaded**
  * **BLAST+**
  * **GIT**, **SVN** (for installation and updating)
* **Requirements installed with `make install`**
  * CG-Pipeline
  * Schedule::SGELK
  * VCF Tools and Vcf.pm
  * Samtools v1.1 or newer
    * bcftools
    * wgsim if you are simulating reads
    * bgzip
    * tabix
  * PHAST
  * Varscan
  * SNAP
  * RAxML
  * Smalt
* Optional "requirements"
  * PhyML
  * FreeBayes

Installation
------------
* `make install`
* `make env` - update `PATH` and `PERL5LIB` in the `~/.bashrc` file.
* `make check` - check and see if you have all the prerequisites
* `make test` - run a test phage dataset provided by CFSAN
* `make help` - for other `make` options
* `make clean` - clean up an old installation in preparation for a new installation
* `make install-*` - Many other installation options are available including but not limited to:
  * `make install-smalt`
  * `make install-CGP`
  * `make install-samtools`
* `make clean-*` - Every `make install` command comes with a `make clean` command, e.g.:
  * `make clean-CGP`

Upgrading
---------
### By stable releases
Unfortunately the best way to get the next stable release is to download the full version like usual, followed by `make install`.  If successful, then delete the directory containing the older version.

    cd ~/tmp
    wget http://latest/release.tar.gz
    tar zxvf release.tar.gz
    cd Lyve-SET
    make install # takes 10-20 minutes to download packages on broadband; install
    cd ~/bin
    rm -r Lyve-SET && mv ~/tmp/Lyve-SET .

### By `git`
    git pull -u origin master
    make clean
    make install
