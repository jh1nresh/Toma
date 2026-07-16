#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "Toma.xcodeproj")

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

app_target = project.new_target(:application, "Toma", :ios, "17.0")
test_target = project.new_target(:unit_test_bundle, "TomaTests", :ios, "17.0")
test_target.add_dependency(app_target)
ui_test_target = project.new_target(:ui_test_bundle, "TomaUITests", :ios, "17.0")
ui_test_target.add_dependency(app_target)

app_group = project.main_group.new_group("Toma", "Toma")
test_group = project.main_group.new_group("TomaTests", "TomaTests")
ui_test_group = project.main_group.new_group("TomaUITests", "TomaUITests")

Dir.glob(File.join(ROOT, "Toma", "**", "*.swift")).sort.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "Toma") + "/")
  reference = app_group.new_file(relative)
  app_target.source_build_phase.add_file_reference(reference)
end

info_reference = app_group.new_file("Info.plist")
info_reference.include_in_index = "1"

assets_reference = app_group.new_file("Assets.xcassets")
app_target.resources_build_phase.add_file_reference(assets_reference)

private_sprite_phase = app_target.new_shell_script_build_phase("Copy private pet sprite for local Debug builds")
private_sprite_phase.always_out_of_date = "1"
private_sprite_phase.shell_path = "/bin/sh"
private_sprite_phase.shell_script = <<~'SCRIPT'
  set -eu

  source_path="${SRCROOT}/Toma/Resources/pet-sprites.png"
  bundle_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/pet-sprites.png"

  if [ "${CONFIGURATION}" = "Debug" ] && [ -f "$source_path" ]; then
    /bin/mkdir -p "$(/usr/bin/dirname "$bundle_path")"
    /bin/cp -f "$source_path" "$bundle_path"
  else
    /bin/rm -f "$bundle_path"
  fi
SCRIPT

Dir.glob(File.join(ROOT, "TomaTests", "**", "*.swift")).sort.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "TomaTests") + "/")
  reference = test_group.new_file(relative)
  test_target.source_build_phase.add_file_reference(reference)
end

Dir.glob(File.join(ROOT, "TomaUITests", "**", "*.swift")).sort.each do |path|
  relative = path.delete_prefix(File.join(ROOT, "TomaUITests") + "/")
  reference = ui_test_group.new_file(relative)
  ui_test_target.source_build_phase.add_file_reference(reference)
end

app_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "io.jeezlabs.toma"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["INFOPLIST_FILE"] = "Toma/Info.plist"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["SWIFT_VERSION"] = "5.0"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["MARKETING_VERSION"] = "0.1.0"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["DEVELOPMENT_TEAM"] = "JC6858UYM9"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  settings["ENABLE_PREVIEWS"] = "YES"
end

test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "io.jeezlabs.toma.tests"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["SWIFT_VERSION"] = "5.0"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Toma.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Toma"
  settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
end

ui_test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "io.jeezlabs.toma.uitests"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["SWIFT_VERSION"] = "5.0"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["TEST_TARGET_NAME"] = "Toma"
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target, launch_target: true)
scheme.add_build_target(ui_test_target, false)
scheme.add_test_target(ui_test_target)
scheme.save_as(PROJECT_PATH, "Toma", true)

puts "Generated #{PROJECT_PATH}"
