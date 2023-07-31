.PHONY: test clean qtest deploy dist
APP_VERSION:=$(shell cat VERSION | head -1)
GIT_COMMIT:=$(shell git describe --dirty --always)
GIT_BRANCH:=$(shell git rev-parse --abbrev-ref HEAD -- | head -1)
BUILD_USER:=$(shell whoami)
BUILD_DATE:=$(shell date +"%Y-%m-%d")
BINARY:=ovs-exporter
VERBOSE:=-v
PROJECT=github.com/greenpau/ovs_exporter
PKG_DIR=pkg/ovs_exporter
BUILD_OS:=linux
BUILD_ARCH:=amd64

all:
	@echo "Version: $(APP_VERSION), Branch: $(GIT_BRANCH), Revision: $(GIT_COMMIT)"
	@echo "Build for $(BUILD_OS)-$(BUILD_ARCH) on $(BUILD_DATE) by $(BUILD_USER)"
	@rm -rf ./bin/$(BUILD_OS)-$(BUILD_ARCH)
	@mkdir -p bin/$(BUILD_OS)-$(BUILD_ARCH)
	@GOOS=$(BUILD_OS) GOARCH=$(BUILD_ARCH) CGO_ENABLED=0 GOPROXY=https://goproxy.cn go build -o ./bin/$(BUILD_OS)-$(BUILD_ARCH)/$(BINARY) $(VERBOSE) \
		-ldflags="-w -s \
		-X github.com/prometheus/common/version.Version=$(APP_VERSION) \
		-X github.com/prometheus/common/version.Revision=$(GIT_COMMIT) \
		-X github.com/prometheus/common/version.Branch=$(GIT_BRANCH) \
		-X github.com/prometheus/common/version.BuildUser=$(BUILD_USER) \
		-X github.com/prometheus/common/version.BuildDate=$(BUILD_DATE) \
		-X $(PROJECT)/$(PKG_DIR).appName=$(BINARY) \
		-X $(PROJECT)/$(PKG_DIR).appVersion=$(APP_VERSION) \
		-X $(PROJECT)/$(PKG_DIR).gitBranch=$(GIT_BRANCH) \
		-X $(PROJECT)/$(PKG_DIR).gitCommit=$(GIT_COMMIT) \
		-X $(PROJECT)/$(PKG_DIR).buildUser=$(BUILD_USER) \
		-X $(PROJECT)/$(PKG_DIR).buildDate=$(BUILD_DATE)" \
		-gcflags="all=-trimpath=$(GOPATH)/src" \
		-asmflags="all=-trimpath $(GOPATH)/src" \
		./cmd/ovs_exporter/*.go
	@echo "Done!"

test: all
	@mkdir -p .coverage;\
		rm -rf ./pkg/ovs_exporter/ovs_exporter.test;\
		go test -c $(VERBOSE) -coverprofile=.coverage/coverage.out ./pkg/ovs_exporter/*.go;\
		mv ./ovs_exporter.test ./pkg/ovs_exporter/ovs_exporter.test;\
		chmod +x ./pkg/ovs_exporter/ovs_exporter.test;\
		sudo ./pkg/ovs_exporter/ovs_exporter.test -test.v -test.testlogfile ./.coverage/test.log -test.coverprofile ./.coverage/coverage.out
	@echo "PASS: core tests"
	@echo "OK: all tests passed!"

coverage:
	@go tool cover -html=.coverage/coverage.out -o .coverage/coverage.html
	@go tool cover -func=.coverage/coverage.out

clean:
	@rm -rf bin/
	@rm -rf dist/
	@echo "OK: clean up completed"

dep:
	@echo "Making dependencies check ..."
	@go get -u golang.org/x/lint/golint
	@go get -u golang.org/x/tools/cmd/godoc
	@go get -u github.com/kyoh86/richgo
	@go get -u github.com/greenpau/versioned/cmd/versioned
	@go get -u github.com/google/addlicense

deploy:
	@sudo rm -rf /usr/sbin/$(BINARY)
	@sudo cp ./bin/$(BUILD_OS)-$(BUILD_ARCH)/$(BINARY) /usr/sbin/$(BINARY)
	@sudo usermod -a -G openvswitch ovs_exporter
	@sudo chmod g+w /var/run/openvswitch/db.sock
	@sudo setcap cap_sys_admin,cap_sys_nice,cap_dac_override+ep /usr/sbin/$(BINARY)

qtest:
	@./bin/$(BUILD_OS)-$(BUILD_ARCH)/$(BINARY) -version
	@sudo ./bin/$(BUILD_OS)-$(BUILD_ARCH)/$(BINARY) -web.listen-address 0.0.0.0:5000 -log.level debug -ovs.poll-interval 5

dist: all
	@mkdir -p ./dist
	@rm -rf ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)
	@mkdir -p ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)
	@cp ./bin/$(BUILD_OS)-$(BUILD_ARCH)/$(BINARY) ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)/
	@cp ./README.md ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)/
	@cp LICENSE ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)/
	@cp assets/systemd/add_service.sh ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)/install.sh
	@chmod +x ./dist/$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)/*.sh
	@cd ./dist/ && tar -cvzf ./$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH).tar.gz ./$(BINARY)-$(APP_VERSION).$(BUILD_OS)-$(BUILD_ARCH)

license:
	@addlicense -c "Paul Greenberg greenpau@outlook.com" -y 2020 pkg/*/*.go

release: license
	@echo "Making release"
	@go mod tidy
	@go mod verify
	@if [ $(GIT_BRANCH) != "main" ]; then echo "cannot release to non-main branch $(GIT_BRANCH)" && false; fi
	@git diff-index --quiet HEAD -- || ( echo "git directory is dirty, commit changes first" && git status && false )
	@versioned -patch
	@echo "Patched version"
	@git add VERSION
	@git commit -m "released v`cat VERSION | head -1`"
	@git tag -a v`cat VERSION | head -1` -m "v`cat VERSION | head -1`"
	@git push
	@git push --tags
	@@echo "If necessary, run the following commands:"
	@echo "  git push --delete origin v$(APP_VERSION)"
	@echo "  git tag --delete v$(APP_VERSION)"
