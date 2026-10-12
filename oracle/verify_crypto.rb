# Reverse-direction oracle: decrypts ciphertexts produced by the CRYSTAL
# port with the ORIGINAL activesupport 8.1.4 gem.
#
#   ruby oracle/verify_crypto.rb <file.tsv>
#
# Input lines: "<json_value>\t<purpose>\t<token>"
#   json_value — JSON dump of the payload the Crystal side encrypted
#   purpose    — purpose string or "" for none
#   token      — encrypt_and_sign output from Crystal
# Output: "<line_no>\tOK" or "<line_no>\tFAIL <detail>" (exit 1 on any FAIL).
# The Crystal spec (spec/crypto_oracle_spec.cr) shells out to this script.

require "active_support/all"
require "active_support/message_encryptor"

SECRET = "0123456789abcdef0123456789abcdef"

def decrypt(token, purpose)
  crypt = ActiveSupport::MessageEncryptor.new(SECRET, cipher: "aes-256-gcm", serializer: :json)
  crypt.decrypt_and_verify(token, purpose: purpose.empty? ? nil : purpose)
rescue ActiveSupport::MessageEncryptor::InvalidMessage
  nil
end

path = ARGV[0] or abort "usage: verify_crypto.rb <file.tsv>"
failed = 0
File.readlines(path).each_with_index do |line, i|
  line = line.chomp
  next if line.empty?
  expected_json, purpose, token = line.split("\t", 3)
  actual = decrypt(token, purpose.to_s)
  actual_json = JSON.generate(actual)
  if actual_json == expected_json
    puts "#{i + 1}\tOK"
  else
    failed += 1
    puts "#{i + 1}\tFAIL expected=#{expected_json} got=#{actual_json}"
  end
end
abort "FAILURES: #{failed}" if failed > 0
