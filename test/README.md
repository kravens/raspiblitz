# Running tests

## Install bats
```
sudo apt install bats
```

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
```

## Python unit tests
```
pip install requests
python3 -m unittest -v test_ip2tor_pay.py
```
