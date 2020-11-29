# docker run command:  docker run -d -p 2049:2049/tcp --privileged -v /etc/shared --name nfs-server nfs:latest

FROM behance/docker-base:2.6-ubuntu-18.04

ENV SHARED=/etc/shared

# install dependencies
RUN apt update -y
RUN apt install -y nfs-kernel-server inotify-tools -qq

# make export directory, remove restrictive permissions, and allow all access
RUN mkdir -p $SHARED && chown nobody:nogroup $SHARED && chmod 777 $SHARED

VOLUME $SHARED

COPY nfs/init .

CMD ["./init"]
