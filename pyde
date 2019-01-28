FROM pydebase
COPY ./init.sh /
ENTRYPOINT ["/init.sh"]
CMD []
