# get the caddy executable
FROM caddy AS caddy-build

# get the go executable 
FROM golang as go

FROM hypernetlabs/galileo-ide:linux AS galileo-ide
	
# Final build stage
FROM algorand/stable

# enable noninteractive installation of deadsnakes/ppa
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata

# install node, python, go, java, and other tools
RUN apt update -y && apt install vim tmux curl zip unzip supervisor git software-properties-common -y && \
	add-apt-repository -y ppa:deadsnakes/ppa && \
	apt-get update -y && \
	apt-get install -y python3.8 python3-pip python3-dev libsecret-1-dev && \
    curl -fsSL https://deb.nodesource.com/setup_12.x | bash - && \
	apt install -y nodejs && \
	curl https://rclone.org/install.sh | bash 

# get the go runtime
COPY --from=go /go /go
COPY --from=go /usr/local/go /usr/local/go
ENV PATH $PATH:/usr/local/go/bin:/home/galileo:/home/galileo/.local/bin

# add galileo non-root user
RUN useradd -ms /bin/bash galileo
COPY .theia /home/galileo/.theia

# get the IDE
COPY --from=galileo-ide --chown=galileo /theia /home/galileo/.galileo-ide

# get the Caddy server executable
# copy the caddy server build into this container
COPY --from=caddy-build /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/
RUN chmod a+rwx /etc/Caddyfile
RUN chmod -R a+rwx /tmp/

# edit the node configuration file for operating as a relay node
RUN cp -r /root/node/* /home/galileo/. && \
	cp /home/galileo/data/config.json.example /home/galileo/data/config.json && \
	sed -i 's/"NetAddress": "",/"NetAddress": ":4161",/g' /home/galileo/data/config.json && \
	sed -i 's/"EnableDeveloperAPI": false,/"EnableDeveloperAPI": true,/g' /home/galileo/data/config.json && \
	sed -i 's/"EndpointAddress": "127.0.0.1:0",/"EndpointAddress": "127.0.0.1:8080",/g' /home/galileo/data/config.json && \
	sed -i 's/"IncomingConnectionsLimit": 750,/"IncomingConnectionsLimit": 750,/g' /home/galileo/data/config.json && \
	chmod -R a+rwx /home/galileo

# switch to non-root user
USER galileo
WORKDIR /home/galileo/.galileo-ide
	
# get superviserd
COPY supervisord.conf /etc/

# rclone configuration file 
COPY rclone.conf /home/galileo/.config/rclone/rclone.conf

# set environment variable to look for plugins in the correct directory
ENV SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/galileo/.galileo-ide/plugins
ENV USE_LOCAL_GIT true

ENV ALGORAND_DATA /home/galileo/data

# # set login credintials and write them to text file
ENV USERNAME "a"
ENV PASSWORD "a"
RUN echo "basicauth /* {" >> /tmp/hashpass.txt && \
    echo "    {env.USERNAME}" $(caddy hash-password -plaintext $(echo $PASSWORD)) >> /tmp/hashpass.txt && \
    echo "}" >> /tmp/hashpass.txt

ENTRYPOINT ["sh", "-c", "supervisord"]