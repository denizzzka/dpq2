DFILES = connection.d answer.d libpq.di
DC = dmd
COMMON = $(DC) $(DFILES) -w -wi
DEBUG := $(COMMON) -g -debug -debug=5 -Dddoc
UNITTEST = $(DEBUG) -unittest
RELEASE := $(COMMON) -release

unittest:
	$(UNITTEST)

debug:
	$(DEBUG)

release:
	$(RELEASE)

clean:
	rm -rf *.o
	rm -rf doc/*
