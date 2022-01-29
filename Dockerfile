FROM texlive/texlive:latest

RUN ["apt-get", "update"]
RUN ["apt-get", "install", "--yes", "jq"]

# install custom fonts
ADD ["https://github.com/cormullion/juliamono/releases/download/v0.043/JuliaMono-ttf.tar.gz", "/tmp/juliamono.tar.gz"]
RUN ["mkdir", "-p", "/usr/share/fonts/juliamono"]
RUN ["tar", "-xz", "-C", "/usr/share/fonts/juliamono", "-f", "/tmp/juliamono.tar.gz"]

COPY ["latexmk-release.bash", "/bin/latexmk-release"]
RUN ["chmod", "+x", "/bin/latexmk-release"]
ENTRYPOINT ["/bin/latexmk-release"]
