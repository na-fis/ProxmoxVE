#!/usr/bin/env bash

# This script is used by both the initial ARR-Stack installation 
# and the catch-up upgrade process.

function install_agregarr() {
    msg_info "Installing Agregarr Dependencies"
    $STD apt-get update
    $STD apt-get install -y ffmpeg libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev unzip
    msg_ok "Installed Agregarr Dependencies"

    msg_info "Installing Fonts"
    mkdir -p /usr/share/fonts/truetype/poster-fonts
    cd /usr/share/fonts/truetype/poster-fonts || exit
    # List of fonts mirrored from Dockerfile
    for font in "bebasneue/BebasNeue-Regular.ttf" "anton/Anton-Regular.ttf" "creepster/Creepster-Regular.ttf" \
                "bangers/Bangers-Regular.ttf" "abrilfatface/AbrilFatface-Regular.ttf" "lato/Lato-Regular.ttf" \
                "pacifico/Pacifico-Regular.ttf" "greatvibes/GreatVibes-Regular.ttf" "nosifer/Nosifer-Regular.ttf" \
                "bungee/Bungee-Regular.ttf" "pressstart2p/PressStart2P-Regular.ttf" "courierprime/CourierPrime-Regular.ttf"; do
        wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/${font}"
    done
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/fredoka/Fredoka[wdth,wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/roboto/Roboto[wdth,wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter[opsz,wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/jetbrainsmono/JetBrainsMono[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/dancingscript/DancingScript[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/raleway/Raleway[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/orbitron/Orbitron[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/Cinzel[wght].ttf"
    wget -q "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond[wght].ttf"
    
    wget -q https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip
    unzip -q Fira_Code_v6.2.zip
    mv ttf/FiraCode-Bold.ttf .
    rm -rf Fira_Code_v6.2.zip ttf/ woff/ woff2/ variable_ttf/
    fc-cache -fv
    msg_ok "Installed Fonts"

    msg_info "Installing yt-dlp"
    wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp
    chmod a+rx /usr/local/bin/yt-dlp
    msg_ok "Installed yt-dlp"

    msg_info "Cloning and Building Agregarr"
    mkdir -p /var/lib/agregarr/
    mkdir -p /opt/agregarr
    chmod 775 /var/lib/agregarr/
    git clone https://github.com/agregarr/agregarr.git /opt/agregarr
    cd /opt/agregarr || exit
    $STD CYPRESS_INSTALL_BINARY=0 yarn install
    $STD yarn build
    msg_ok "Built Agregarr"

    msg_info "Creating Agregarr Service"
    cat <<EOF >/etc/systemd/system/agregarr.service
[Unit]
Description=Agregarr Service
After=network.target

[Service]
User=root
Group=root
UMask=0000
Type=exec
WorkingDirectory=/opt/agregarr
Environment=NODE_ENV=production
Environment=CONFIG_DIRECTORY=/var/lib/agregarr
ExecStart=/usr/bin/yarn start
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable -q --now agregarr.service
    msg_ok "Created Agregarr Service"
}

# Run the installation
install_agregarr
