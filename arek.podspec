Pod::Spec.new do |s|
  s.name             = 'arek'
  s.version          = '4.0.2'
  s.summary          = 'AREK is a clean and easy to use wrapper over any kind of iOS permission.'
  s.homepage         = 'https://github.com/liweihan/arek'
  s.license          = { :type => 'MIT', :file => 'LICENSE'}
  s.author           = { 'Ennio Masi' => 'ennio.masi@gmail.com' }
  # This fork has published no release: its tag 4.0.2 is ennioma/arek's, whose core imports PMAlertController, which
  # this podspec does not declare. The commit is one of this repository without that import (develop at a79a571);
  # replace it with `:tag => s.version.to_s` when a release is tagged. scripts/check-package.sh reads the source this names.
  s.source           = { :git => 'https://github.com/liweihan/arek.git', :commit => 'a79a5717e63d0639e526ed500b64f9c9b72e326c' }
  s.social_media_url = 'https://twitter.com/ennioma'
  s.ios.deployment_target = '12.0'
  s.swift_version    = '5.0'
  s.exclude_files = 'Example/*'

  # Every source file belongs to a subspec and the root declares none, so that `pod 'arek/Camera'` is Core + Camera and
  # `pod 'arek'` is the union of the subspecs (scripts/check-package.sh checks both against Package.swift).

  s.subspec 'Core' do |ss|
    ss.source_files = 'code/Classes/Core/**/*.swift'
  end

  s.subspec 'Bluetooth' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/Bluetooth/*.swift'
    ss.frameworks = 'CoreBluetooth'
  end

  s.subspec 'Camera' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekCamera.swift'
    ss.frameworks = 'AVFoundation'
  end

  s.subspec 'CloudKit' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekCloudKit.swift'
    ss.frameworks = 'CloudKit'
  end

  s.subspec 'Contacts' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekContacts.swift'
    ss.frameworks = 'Contacts'
  end

  s.subspec 'Events' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekEvents.swift'
    ss.frameworks = 'EventKit'
  end

  s.subspec 'Health' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekHealth.swift'
    ss.frameworks = 'HealthKit'
  end

  s.subspec 'Location' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/Location/*.swift'
    ss.frameworks = 'CoreLocation'
  end

  s.subspec 'MediaLibrary' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekMediaLibrary.swift'
    ss.frameworks = 'MediaPlayer'
  end

  s.subspec 'Microphone' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekMicrophone.swift'
    ss.frameworks = 'AVFoundation'
  end

  s.subspec 'Motion' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekMotion.swift'
    ss.frameworks = 'CoreMotion'
  end

  s.subspec 'Notifications' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekNotifications.swift'
    ss.frameworks = 'UserNotifications'
  end

  s.subspec 'Photos' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekPhoto.swift'
    ss.frameworks = 'Photos'
  end

  s.subspec 'Reminders' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekReminders.swift'
    ss.frameworks = 'EventKit'
  end

  s.subspec 'Siri' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekSiri.swift'
    ss.frameworks = 'Intents'
  end

  s.subspec 'SpeechRecognizer' do |ss|
    ss.dependency 'arek/Core'
    ss.source_files = 'code/Classes/Permissions/ArekSpeechRecognizer.swift'
    ss.frameworks = 'Speech'
  end

end
