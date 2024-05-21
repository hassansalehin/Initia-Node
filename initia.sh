
# Updating and installing necessary packages
sudo apt update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -yq install curl git jq build-essential gcc unzip wget lz4

# Installing Go
cd $HOME
GO_VERSION="1.22.2"
wget "https://golang.org/dl/go$GO_VERSION.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$GO_VERSION.linux-amd64.tar.gz"
rm "go$GO_VERSION.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile
go version

# Setting environment variables
echo export INITIA_TAG=${INITIA_TAG} >> $HOME/.bash_profile
echo export SLINKY_TAG=${SLINKY_TAG} >> $HOME/.bash_profile
echo export CHAIN_ID=${CHAIN_ID} >> $HOME/.bash_profile
echo export MONIKER=${MONIKER} >> $HOME/.bash_profile
source $HOME/.bash_profile

# Configuring system limits
echo '* soft nofile 65535' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65535' | sudo tee -a /etc/security/limits.conf

# Cloning and building Slinky
git clone https://github.com/skip-mev/slinky.git
cd slinky
git checkout $SLINKY_TAG
make build

# Setting up Slinky service
sudo tee /etc/systemd/system/oracled.service > /dev/null << EOF
[Unit]
Description=oracle

[Service]
Type=simple
User=root
ExecStart=/root/slinky/build/slinky --oracle-config-path /root/slinky/config/core/oracle.json --market-map-endpoint 0.0.0.0:9090
Restart=on-abort
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=initiad
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl enable oracled
systemctl restart oracled

# Cloning and building Initia
cd $HOME
git clone https://github.com/initia-labs/initia
cd initia
git checkout $INITIA_TAG
make install
initiad version
cp $HOME/go/bin/initiad /usr/local/bin/initiad

# Initializing Initia
initiad init $MONIKER --chain-id $CHAIN_ID
curl -Ls https://initia.s3.ap-southeast-1.amazonaws.com/initiation-1/genesis.json > $HOME/.initia/config/genesis.json

# Setting peers and seeds
PEERS="a3660a8b7a0d88b12506787b26952930f1774fc2@65.21.69.53:48656,e3ac92ce5b790c76ce07c5fa3b257d83a517f2f6@178.18.251.146:30656,2692225700832eb9b46c7b3fc6e4dea2ec044a78@34.126.156.141:26656,2a574706e4a1eba0e5e46733c232849778faf93b@84.247.137.184:53456,40d3f977d97d3c02bd5835070cc139f289e774da@168.119.10.134:26313,1f6633bc18eb06b6c0cab97d72c585a6d7a207bc@65.109.59.22:25756,4a988797d8d8473888640b76d7d238b86ce84a2c@23.158.24.168:26656,e3679e68616b2cd66908c460d0371ac3ed7795aa@176.34.17.102:26656,d2a8a00cd5c4431deb899bc39a057b8d8695be9e@138.201.37.195:53456,329227cf8632240914511faa9b43050a34aa863e@43.131.13.84:26656,517c8e70f2a20b8a3179a30fe6eb3ad80c407c07@37.60.231.212:26656,07632ab562028c3394ee8e78823069bfc8de7b4c@37.27.52.25:19656,028999a1696b45863ff84df12ebf2aebc5d40c2d@37.27.48.77:26656,3c44f7dbb473fee6d6e5471f22fa8d8095bd3969@185.219.142.137:53456,8db320e665dbe123af20c4a5c667a17dc146f4d0@51.75.144.149:26656,c424044f3249e73c050a7b45eb6561b52d0db456@158.220.124.183:53456,767fdcfdb0998209834b929c59a2b57d474cc496@207.148.114.112:26656,edcc2c7098c42ee348e50ac2242ff897f51405e9@65.109.34.205:36656,140c332230ac19f118e5882deaf00906a1dba467@185.219.142.119:53456,4eb031b59bd0210481390eefc656c916d47e7872@37.60.248.151:53456,ff9dbc6bb53227ef94dc75ab1ddcaeb2404e1b0b@178.170.47.171:26656,ffb9874da3e0ead65ad62ac2b569122f085c0774@149.28.134.228:26656"
SEEDS="2eaa272622d1ba6796100ab39f58c75d458b9dbc@34.142.181.82:26656,c28827cb96c14c905b127b92065a3fb4cd77d7f6@testnet-seeds.whispernode.com:25756"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.initia/config/config.toml

# Enabling oracle in the configuration
sed -i '/^\[oracle\]$/,/^\[/ s/^enabled = .*/enabled = "true"/; s/^oracle_address = .*/oracle_address = "127.0.0.1:8080"/' /root/.initia/config/app.toml

# Setting minimum gas prices
sed -i -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.15uinit,0.01uusdc\"/" $HOME/.initia/config/app.toml

# Setting up Initia service
sudo tee /etc/systemd/system/initiad.service > /dev/null << EOF
[Unit]
Description=initiad

[Service]
Type=simple
User=root
ExecStart=/root/go/bin/initiad start
Restart=on-abort
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=initiad
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Enabling and starting Initia service
systemctl enable initiad
systemctl start initiad
systemctl stop initiad

# Resetting Tendermint and applying snapshot
initiad tendermint unsafe-reset-all --home $HOME/.initia --keep-addr-book
curl -o - -L $SNAPSHOT_LINK | lz4 -c -d - | tar -x -C $HOME/.initia
systemctl start initiad

echo "============================================================"
echo "Installation complete!"
echo "============================================================"
