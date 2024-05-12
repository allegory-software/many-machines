
install_lazygit() {
	must dry mkdir -p tmp
	must cd tmp
	local file=lazygit_0.41.0_Linux_x86_64.tar.gz
	must dry wget https://github.com/jesseduffield/lazygit/releases/download/v0.41.0/$file
	must dry tar xzvf $file
	must dry mv -f lazygit /usr/bin/
}
