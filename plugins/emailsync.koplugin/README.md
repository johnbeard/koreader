# EmailSync plugin

A plugin which can pull email down from an IMAP mailbox and import files found
therein.


## IMAP notes

IMAP is a text based protocol. Commands look something like:

```
<tag> <command> [parameters...]
```

The `tag` can be anything, it's used to identify the replies to your command.
The `command` can be something like `fetch` or `search` and the available
`parameters` depend on the command.

You can test commands on a mailbox with something
like the following (for an SSL connection):

```
openssl s_client -crlf -connect imap.gmail.com:993
```

When the connection is open, login to your mailbox:

```
a login douglas.adams douglas42
```