#!/bin/bash

pandoc -t html --standalone --self-contained --css ../wording_edits.css --ascii -o d0000-extended-offsetof-v2.html d0000-extended-offsetof-v2.md
