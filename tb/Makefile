# Run every cocotb testbench:   make          (from tb/)
# Stops at the first bench with a failing test.

.PHONY: all fifo record_builder top clean

all: fifo record_builder top

fifo:
	$(MAKE) -C test_async_frame_fifo

record_builder:
	$(MAKE) -C test_record_builder SNAPLEN=16
	$(MAKE) -C test_record_builder SNAPLEN=64

top:
	$(MAKE) -C test_top

clean:
	$(MAKE) -C test_async_frame_fifo clean
	$(MAKE) -C test_record_builder clean SNAPLEN=16
	$(MAKE) -C test_record_builder clean SNAPLEN=64
	$(MAKE) -C test_top clean
	rm -rf */__pycache__ */results*.xml
