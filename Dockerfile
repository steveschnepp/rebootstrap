FROM debian:sid-slim
ADD bootstrap.sh /
RUN sh bootstrap.sh
