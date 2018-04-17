# SQE_Session
Classes to organize the sessions in SQE

## The Session Management in SQE

### Introduction

The session management works on two levels to provide a
fast (re-)creation of sessions.

Since the communication between client and server is done
by many single CGI-calls it would be not wise to create
a valid session always from the scratch, meaning, to 
create a database handler and to check the credentials
again and again.

To prevent this, the SQE_CGI class owns an instance of 
`SQE_Session::Container`, which is accessible for any 
instance of of `SQE_CGI` and provide access to already
defined sessions as instances of `SQE_Session::Session`, 
which are addressed by a session id. 
This includes a valid SQE database handler which by itself
has direct access to the session data.

Thus, normally it is not necessary to use the current
instances of`SQE_Session::Session` or 
`SQE_Session::Container` for writing an 
SQE_CGI application. Any GGI application should be 
created as a child of SQE_CGI to use its magic 
(cf. the description of `SQE_CGI`)

Thus, by calling new() on such a child, the new instance
is always provided by a valid session using the 
CGI paramaters(provided by the Perl CGI)
USER_NAME, PASSWORD, and/or SESSION_ID or throws 
an error if no session could be (re-)created.

A valid `SQE_db` database handler connected with this
session is accessable via `SQE_CGI->{DBH}`.

### Creating a new session

To create a new session, simply pass the parameters
`USERN_NAME` and `PASSWORD` with valid values to any
child of `SQE_CGI`. The CGI will autoamtically set up
a new session with a valid "SQE_db" databasehandler
and retrieve any global user settings from the database.

It's wise to return the id of the created session to
the client which it could use to use the same session
for later calls without the overhead of creating a session
again from the scratch.

### Reusing a session

If a child of `SQE_CGI` is called with the parameter
`SESSION_ID`


