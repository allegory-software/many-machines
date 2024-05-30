
install_lazygit() {
	(
	local VER=0.41.0
	sayn "Installing lazygit $VER ... "
	must cd tmp
	local file=lazygit_${VER}_Linux_x86_64.tar.gz
	on_exit run rm -f $file LICENSE README.md
	must dry wget -q https://github.com/jesseduffield/lazygit/releases/download/v${VER}/$file
	must dry tar xzf $file
	must dry mv -f lazygit /usr/bin/
	which lazygit >/dev/null && say OK
	) || die "Lazygit was NOT installed."
}
