DFILES = connection.d answer.d libpq.di
DC = dmd
COMMONFLAGS = -w -wi
DEBUGFLAGS := $(COMMONFLAGS) -g -debug -debug=5 -Dddoc
RELEASEFLAGS := $(COMMONFLAGS) -release
UNITTESTFLAGS = -unittest

release:
	$(DC) $(DFILES) $(RELEASEFLAGS)

unittest:
	$(DC) $(DFILES) $(DEBUGFLAGS) $(UNITTESTFLAGS)

clean:
	rm -rf *.o $(RES)
	rm -rf doc/*
