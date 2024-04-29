# couchdb-maintenance-mode

> Terminal UI to manage CouchDB cluster's node maintenance mode 

## Usage

```sh
# URL
export COUCH_URL=http://admin:my-password@couchdb-1.local.domain

#
# CouchDB cluster nodes should have a consistant naming, like:
#
# couchdb@host-1.local.domain, couchdb@host-2.local.domain, couchdb@host-3.local.domain
#
# Set COUCHDB_NODE_USER, COUCHDB_NODE_SUFFIX, COUCHDB_NODES to match your setup.
#
export COUCHDB_NODE_USER=couchdb
export COUCHDB_NODE_SUFFIX=.local.domain
export COUCHDB_NODES="host-1 host-2 host-3"

./maintenance_mode
```

## License

Copyright 2024, Jean-Christophe Hoelt

Permission is hereby granted, free of charge, to any person obtaining a copy of 
this software and associated documentation files (the “Software”), to deal in 
the Software without restriction, including without limitation the rights to 
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
of the Software, and to permit persons to whom the Software is furnished to do 
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
SOFTWARE.

