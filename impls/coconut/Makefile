TESTS =

SOURCES_BASE = mal_types.py reader.py printer.py
SOURCES_LISP = step*_*.coco
SOURCES = $(SOURCES_BASE) $(SOURCES_LISP)

all: dist

dist:
		coconut .

%.py: all

clean:
		rm -f *.py

.PHONY: stats tests $(TESTS)

stats: $(SOURCES)
		@wc $^
		@printf "%5s %5s %5s %s\n" `grep -E "^[[:space:]]*#|^[[:space:]]*$$" $^ | wc` "[comments/blanks]"
stats-lisp: $(SOURCES_LISP)
		@wc $^
		@printf "%5s %5s %5s %s\n" `grep -E "^[[:space:]]*#|^[[:space:]]*$$" $^ | wc` "[comments/blanks]"
