DFILES = connection.d answer.d libpq.di
DC = dmd
PQFLAGS = -L-lpq -L-lcom_err
COMMON = $(DC) $(DFILES) $(PQFLAGS) -w -wi -ofdpq2

DEBUG := $(COMMON) -g -debug -debug=5 -Dddoc -lib
UNITTEST = $(DEBUG) -unittest
RELEASE := $(COMMON) -release -lib

unittest:
	$(UNITTEST)

debug:
	$(DEBUG)

release:
	$(RELEASE)

clean:
	rm -rf *.o *.a
	rm -rf doc
