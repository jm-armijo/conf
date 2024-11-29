# conf

Configuration files used for the following programmes:

- vim
- tmux
- bash
- zsh



## tmux

Copy file `tmux/tmux.conf` into the home directory as a hidden file:

```bash
cp tmux/tmux.conf ~/.tmux.conf
```

## zsh

Download oh-my-zsh

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Or check the zsh site for details:

```bash
https://ohmyz.sh/#install
```

Then copy the zsh configuration file:

```bash
cp zsh/zshrc ~/.zshrc
```

Add the syntax highlighting plugin (see instructions here: https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)

```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

Override the agnoster theme:

```bash
cp zsh/agnoster.zsh-theme ~/.oh-my-zsh/themes/agnoster.zsh-theme
```

### Install Powerline fonts

I got the steps from this page: https://fmacedoo.medium.com/oh-my-zsh-with-powerline-fonts-pretty-simple-as-you-deserve-fbe7f6d23723

Clone powerline fonts repo:

```bash
git clone https://github.com/powerline/fonts.git --depth=1
```

Install the fonts:

```bash
cd fonts
./install.sh
```

Remove the cloned repository:

```bash
cd ..
rm -rf fonts
```

Enable powerline fonts in Iterm2:

- Go to Settings -> Profiles -> Text
- Select `Use built-in Powerline glyphs`

## Git

Execute this commands to set all aliases

```bash
./git/aliases.sh
```
