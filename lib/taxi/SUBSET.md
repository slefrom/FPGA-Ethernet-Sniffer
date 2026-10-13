# Taxi subset for the Arty A7 Ethernet sniffer

These files are an unmodified subset of the Taxi transport library by
Alex Forencich / FPGA Ninja, LLC:

    https://github.com/fpganinja/taxi
    commit cc70b270b910d369ab1ad7b3855e76399fd461f1

They are only the sources and constraint scripts the minimal sniffer
needs, kept at their original paths under src/. Taxi is licensed under
the CERN Open Hardware Licence v2 - Strongly Reciprocal (see LICENSE);
the licence and copyright notices must stay with these files.

To use the full library instead, delete this folder and run:

    git submodule add https://github.com/fpganinja/taxi lib/taxi
    git -C lib/taxi checkout cc70b270b910d369ab1ad7b3855e76399fd461f1
