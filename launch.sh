#!/usr/bin/env bash

if [[ $(docker ps -a -q --filter name="{ucdsl-cli}") ]] ; then docker stop ucdsl-cli ; fi

echo "Launch Dockerized UC-DSL tools"
echo "Available launch modes: cli, gui"
echo -n "Select a mode: " && read -r mode

echo "Setup Volumes"

cd ./configvolumes
echo Currently available volumes: $(for f in *.txt ; do printf '%s ' "${f%.txt}" ; done)
cd ..

read -e -p "Select sourcecode volume from list or enter a new absolute path to bind: " code_volume

read -e -p "Select includes volume from list or enter a new absolute path to bind: " incl_volume

code_volume_src="UNSET"
incl_volume_src="UNSET"



cd ./configvolumes
for file in *.txt ; do
    if [[ $file == "$code_volume.txt" ]] ; then
        code_volume_src="$(awk -F = '/^src/{print $NF}' $file)"
    elif [[ $file == "$incl_volume.txt" ]] ; then
        incl_volume_src="$(awk -F = '/^src/{print $NF}' $file)"
    fi
done

if [[ $code_volume_src == "UNSET" ]] ; then
    echo -n "Enter a unique name for the sourcecode volume: " && read -r code_volume_name
    echo "src=$code_volume" > "$code_volume_name.txt"
    code_volume_src=$code_volume
fi

if [[ $incl_volume_src == "UNSET" && $incl_volume ]] ; then
    echo -n "Enter a unique name for the includes volume: " && read -r incl_volume_name
    echo "src=$incl_volume" > "$incl_volume_name.txt"
    incl_volume_src=$incl_volume
fi
cd ..

ucdsl_path="/home/primary/EasyUC/uc-dsl/bin"

if [[ "$mode" == "cli" ]] ; then
    code_dst="/host/srcfiles"
    incl_dst="/host/includes"
    test "$incl_volume_src" == "UNSET" && incl_folder="" || incl_folder="-I $incl_dst"
    test "$incl_volume_src" == "UNSET" && incl_vol="" || incl_vol="-v $incl_volume_src:$incl_dst"
    docker build -t ucdsl-tools -f ucdsl.Dockerfile . || exit $?
    docker run --rm -v "$code_volume_src:$code_dst" \
        $incl_vol -d -i -t --name ucdsl-cli ucdsl-tools /bin/bash || exit $?
    keep_running="y"
    (cd $code_volume_src && printf "All UCI Files in volume:\n$(for f in *.uci ; do printf "$f\n" ; done)\n") || exit $?
    while [[ $keep_running == "y" || $keep_running == "Y" ]] ; do
        (cd $code_volume_src && read -e -p "Enter a *.uci file to run: " uci_script && echo -n $uci_script > ~/.uciname)
        uci_script="$(cat ~/.uciname | tr -d '\n ')" && rm ~/.uciname
        log_fname=$(echo "$uci_script" | sed -e "s/\.uci/_out\.txt/g")
        docker exec -i ucdsl-cli bash -c "$ucdsl_path/ucdsl \
            $incl_folder $code_dst/$uci_script" &> "./outputlogs/$log_fname" \
            || echo "Error code $? occurred while running script!" >&2
        echo -n "Do you want to run another script? [y/N]: " && read -r resp
        keep_running=$resp
    done
    docker stop ucdsl-cli
elif [[ "$mode" == "gui" ]] ; then
    code_dst="/home/headless/srcfiles"
    incl_dst="/home/headless/includes"
    test "$incl_volume_src" == "UNSET" && incl_vol="" || incl_vol="-v $incl_volume_src:$incl_dst"
    docker build -t ucdsl-tools-gui -f ucdsl-gui.Dockerfile . || exit $?
    echo "To connect to the GUI, open your web browser to http://localhost:36901/vnc.html?password=headless"
    docker run --rm --name ucdsl-gui -v "$code_volume_src:$code_dst" \
        $incl_vol -p "36901:6901" -p "35901:5901" ucdsl-tools-gui /bin/bash \
        || echo "Error code $? occurred during run" >&2
fi

echo "End of launch script"
