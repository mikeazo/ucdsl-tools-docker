# UC-DSL Tools Docker

## Usage (Traditional Method)

### Building the Command-Line Interface (CLI) container

To build the image run `docker build -t ucdsl-tools -f ucdsl.Dockerfile .` from inside the cloned repository.

### Running UC DSL files

The best way to run UC DSL files in this docker image is to mount a local folder into the container and run the right commands to execute the UC DSL tools (via the `ucdsl` command).

For example: `docker run -v /PATH/TO/FOLDER/:/host/ -it ucdsl-tools /bin/bash -c "cd /host/PATH/TO/FOLDER && ucdsl -I ANY/INCLUDE/FOLDERS FILENAME.uci"`

That will run the `ucdsl` executable on the provided file with the provided include directory.

### GUI

UC DSL can be run within the Emacs graphical user interface and Proof General. The ucdsl-gui.Dockerfile in this repository sets up a container with a GUI that can be accessed via VNC to use these tools. It is built upon the [accetto/ubuntu-vnc-xfce-g3:24.04](https://accetto.github.io/user-guide-g3/) docker image.

To build this container, run `docker build -t ucdsl-tools-gui -f ucdsl-gui.Dockerfile .` from inside the cloned repository.

To run the built image run `docker run -v /PATH/TO/FOLDER/:/host -p "36901:6901" ucdsl-tools-gui`.

Then to connect to the GUI, open your web browser to
[http://localhost:36901/vnc.html?password=headless](http://localhost:36901/vnc.html?password=headless).

The default password for the VNC connection is *headless*.

## Usage with (New) Convenience Script

There is a new convenience script (`launch.sh`) that will assist in launching either the CLI or GUI version of the tool, even setting up volumes interactively. To start the script, simply run `./launch.sh` from a `Bash` terminal. Then follow the prompts as described below.

* Prompt: `Available launch modes: cli, gui` `Select a mode: `
  * Type `cli` for the command-line interface or `gui` for VNC GUI and press enter.
* Prompt: `Select sourcecode volume from list or enter a new absolute path to bind: `
  * See next section for a detailed explanation.

### Setting up Volumes

The first time you run the launch script, no volumes will be listed above the third prompt. To create Docker `bind mounts` for both the `srcfiles` and `includes` folders (to contain the UCI files and required EasyCrypt types respectively), first type the absolute path to a host folder containing EasyUC scripts (`*.uci` files). For example: `/home/myuser/gitrepo/UCI-Scripts`.

Next you will see the prompt `Select includes volume from list or enter a new absolute path to bind: `.  Repeat the process above, typing the absolute path to the required `EasyCrypt` types folder (containing `*.ec` files).

Finally, assuming you are creating new volumes (and not selecting existing ones), you will also get prompted to give a name for each volume with `Enter a unique name for the [sourcecode/includes] volume: `. This name must not have any special characters or spaces (other than `-` or `_`). For example, if the volume path is `/home/myuser/gitrepo/UCI-Scripts`, you could name your volume `uci_scripts`, but **NOT** `gitrepo/uci_scripts`. These names will be used to select your volumes in future runs of the launch script on your system.

Once all these steps are completed, the appropriate Docker image will be built and run automatically. To terminate the script at any time, press `Ctrl-C`. Post-run cleanup will occur automatically.

## Notes and Troubleshooting

### UCI Script Output

When you run the UCDSL CLI tool via the convenience script, any UCI scripts you run will pipe their output to a text file saved in the `outputlogs` folder. Their file names will be automatically generated with the format `${UCI_filename}_out.txt`.

### Docker Build Issues

Occasionally the `docker build` process for both the `CLI` and `GUI` modes will terminate with an error before finishing. This is typically either a network timeout or cert authentication error. Unfortunately these errors have external causes, so there's nothing we can do in the code to resolve them. However, each step in either Dockerfile will be cached by default, making additional runs of the build essentially start where it left off. In other words, the only work around is to keep trying until it completes successfully. Without any interruptions, `docker build` should take between 10-15 minutes.

### Contact Info

If you have issues with the "Dockerized" UC DSL tools, please email our team at [harden@riversideresearch.org](mailto:harden@riversideresearch.org). For more information about Universal Composability and the UC DSL see the [EasyUC](https://github.com/easyuc) repository.

---

ACKNOWLEDGMENT

This material is based upon work supported by the Defense Advanced Research Projects Agency (DARPA) under Contract No. N66001-22-C-4020. Any opinions, findings, and conclusions or recommendations expressed in this material are those of the author(s) and do not necessarily reflect the views of the Defense Advanced Research Projects Agency (DARPA).

Distribution A: Approved for Public Release
