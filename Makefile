.PHONY: all clean test dialyze

REBAR=@`sh -c "PATH='$(PATH)':support which rebar3||dev/getrebar||echo false"`

all:
	$(REBAR) compile

clean:
	$(REBAR) clean

test:
	$(REBAR) eunit

dialyze:
	$(REBAR) dialyzer
