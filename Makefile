.PHONY: all posh vim
POSH_S = oh-my-posh-setup.sh
VIM_S = vim-setup.sh
unspec: # Fake empty target
all: posh vim
posh:
	chmod +x $(POSH_S)
	./$(POSH_S)
vim:
	chmod +x $(VIM_S)
	./$(VIM_S)

