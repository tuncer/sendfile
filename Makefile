.PHONY: all clean install test

REBAR=@`sh -c "PATH='$(PATH)':support which rebar\
	||support/getrebar||echo false"`

all:
	$(REBAR) compile

clean:
	$(REBAR) clean

install:
	$(REBAR) install

test:
	$(REBAR) eunit
