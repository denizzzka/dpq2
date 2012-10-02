DFILES = connection.d answer.d libpq.di
ONAME = libdpq2
DC = dmd
PQFLAGS = -L-lpq -L-lcom_err
COMMON = $(DC) $(DFILES) $(PQFLAGS) -w -lib -Hf$(ONAME).di -of$(ONAME)

DEBUG := $(COMMON) -g -debug -debug=5
RELEASE := $(COMMON) -release
UNITTEST = $(DEBUG) -unittest

release:
	$(RELEASE)

debug:
	$(DEBUG)

unittest:
	$(UNITTEST)

doc:
	$(RELEASE) -o- -Dddoc

clean:
	rm -rf *.o *.a
	rm -rf doc
