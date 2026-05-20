FROM --platform=linux/amd64 accetto/ubuntu-vnc-xfce-g3:24.04 

ARG SUDO="n"

# run some things as root
USER root

# Update the image 
RUN apt-get update && apt-get upgrade -y

# Setup the dependencies
RUN apt-get install autoconf pkgconf ocaml ocaml-native-compilers camlp4-extra opam libgmp-dev libpcre2-dev pkg-config zlib1g-dev emacs -y
RUN chown -R headless:headless /home/headless /dockerstartup 

USER headless
WORKDIR /home/headless

# Setup OPAM 
RUN opam init --verbose -y && eval $(opam env)

# Setup OPAM dependencies 
RUN opam install -y dune batteries

# Setup Easycrypt
RUN opam switch create 5.4.1 && eval $(opam env) && opam pin -yn add easycrypt https://github.com/EasyCrypt/easycrypt.git && opam install -y --deps-only easycrypt && eval $(opam env)

# Install why3
RUN opam pin -y why3 1.8.2

# Setup the SMT solvers
RUN opam pin -y alt-ergo 2.6.0
USER root
RUN cd /opt && wget https://github.com/Z3Prover/z3/releases/download/z3-4.15.3/z3-4.15.3-x64-glibc-2.39.zip && unzip z3-4.15.3-x64-glibc-2.39.zip && ln -s /opt/z3-4.15.3-x64-glibc-2.39/bin/z3 /usr/bin/z3 && rm /opt/z3-4.15.3-x64-glibc-2.39.zip && cd /

# Modify the sudoers file for headless user
RUN echo "headless ALL = (ALL:ALL) NOPASSWD: /usr/bin/chown" >> /etc/sudoers.d/headless

USER headless
WORKDIR /home/headless

# Setup easycrypt
RUN opam install -y easycrypt && eval $(opam env) && easycrypt why3config

# Setup Bisect_ppx
RUN opam install -y bisect_ppx --update-invariant

# Setup UC-DSL
RUN cd ~ && git clone https://github.com/easyuc/EasyUC.git && cd EasyUC/uc-dsl/ && eval $(opam env) && echo "/home/headless/.opam/5.4.1/lib/easycrypt/theories" | ./configure && ./build && ./install-opam

# Setup Emacs
COPY emacs /home/headless/.emacs
COPY alias_cmds.sh /home/headless/alias_cmds.sh
USER root
RUN chmod +x /home/headless/alias_cmds.sh
RUN chown headless:headless /home/headless/alias_cmds.sh
RUN chown headless:headless /home/headless/.emacs && cp /home/headless/EasyUC/uc-dsl/emacs/ucdsl-mode.el /usr/share/emacs/site-lisp/
USER headless
WORKDIR "/home/headless"
RUN emacs --batch --eval "(progn (package-refresh-contents) (package-install 'proof-general))"
RUN pgdir="$(find /home/headless/.emacs.d/elpa/proof-general-*.[!a-z]* -maxdepth 0 -print -quit | tr -d '\n ')" && echo "$pgdir" > ~/.pgdir
RUN pgdir="$(cat ~/.pgdir | tr -d '\n ')" && mkdir "${pgdir}/ucdsl-interpreter/"
RUN pgdir="$(cat ~/.pgdir | tr -d '\n ')" && cp /home/headless/EasyUC/uc-dsl/emacs/ucdsl-interpreter.el "${pgdir}/ucdsl-interpreter/" && sed -i '51 i \ \ \ \ \ \ (ucdsl-interpreter "UC DSL Interpreter" "uci")' "${pgdir}/generic/proof-site.el"
RUN pgdir="$(cat ~/.pgdir | tr -d '\n ')" && emacs --batch --eval "(progn (add-to-list 'load-path (expand-file-name \"${pgdir}/generic/\")) (byte-compile-file (expand-file-name \"${pgdir}/generic/proof-site.el\")))"

RUN mkdir srcfiles && mkdir includes

# Setup the environment
RUN opam env >> /home/headless/.bashrc

# Add the alias script to the .profile
RUN if [ $SUDO = 'y' ] ; then echo "/home/headless/alias_cmds.sh" >> /home/headless/.profile ; fi
RUN if [ $SUDO = 'y' ] ; then echo ". ~/.profile" > /home/headless/.xsessionrc ; fi

# Run
