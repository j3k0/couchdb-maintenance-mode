FROM couchdb:3

# Install dependencies needed for the script
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq whiptail && \
    rm -rf /var/lib/apt/lists/*


# Expose the default CouchDB port
EXPOSE 5984

# Set the default command to start CouchDB
CMD ["couchdb"]
