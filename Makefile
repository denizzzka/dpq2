DFILES = connection.d answer.d libpq.di
DC = dmd
PQFLAGS = -L-lpq -L-lcom_err
COMMON = $(DC) $(DFILES) $(PQFLAGS) -w -lib -ofdpq2

DEBUG := $(COMMON) -g -debug -debug=5
RELEASE := $(COMMON) -release
UNITTEST = $(DEBUG) -unittest

unittest:
	$(UNITTEST)

debug:
	$(DEBUG)

release:
	$(RELEASE)

doc:
	$(RELEASE) -o- -Dddoc

clean:
	rm -rf *.o *.a
	rm -rf doc
