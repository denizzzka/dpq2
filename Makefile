DFILES = libpq.di connection.d query.d answer.d unittests_main.d
ONAME = libdpq2
DC = dmd
PQFLAGS = -L-lpq -L-lcom_err
COMMON = $(DC) $(DFILES) $(PQFLAGS) -w -d -Hf$(ONAME).di -of$(ONAME)

DEBUG = $(COMMON) -g -debug -lib
RELEASE = $(COMMON) -release -lib
UNITTEST = $(COMMON) -g -debug -unittest

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
	rm -f $(ONAME)
	rm -f $(ONAME).di
