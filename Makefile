all: build

build:
	odin build . -out:pomodoro

run: build
	./pomodoro

clean:
	rm -f pomodoro
