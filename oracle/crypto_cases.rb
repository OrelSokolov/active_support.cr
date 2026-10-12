# Oracle cases for ActiveSupport::KeyGenerator / CachingKeyGenerator /
# MessageEncryptor (crypto foundation for credentials, signed/encrypted
# cookies and AR encryption).
#
# Run against the ORIGINAL gem:
#   ruby oracle/crypto_cases.rb > oracle/crypto_expected.yml
#
# Each line: "<case_id>\t<rendered result>". Mirrored 1:1 in
# spec/crypto_oracle_spec.cr. Values captured from activesupport 8.1.4.
#
# KeyGenerator cases are deterministic → byte-comparable hex digests.
# MessageEncryptor uses a random IV, so ciphertexts can't be reproduced
# byte-for-byte. Each encryptor case therefore emits TWO lines:
#   <id>_t  — the Ruby-generated ciphertext (stored verbatim)
#   <id>_r  — render(decrypt_and_verify(ciphertext)) — what the Crystal
#             port must obtain when decrypting the _t line with the same
#             secret/options.
# The reverse direction (Crystal encrypts → Ruby decrypts) is covered by
# oracle/verify_crypto.rb, which the Crystal spec shells out to.

require "active_support/all"
require "active_support/key_generator"
require "active_support/message_encryptor"

ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata = true # Rails 8.1 app default

def render(v)
  case v
  when true, false, Integer, Float, String then v.inspect
  when Symbol then ":#{v}"
  when nil then "nil"
  when Array then "A[#{v.map { |e| render(e) }.join(',')}]"
  when Hash then "H{#{v.sort_by { |k, _| k.to_s }.map { |k, val| "#{render(k)}=>#{render(val)}" }.join(',')}}"
  when Exception then "raise:#{v.class.name}"
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

SECRET = "0123456789abcdef0123456789abcdef" # 32 bytes, aes-256-gcm key

# --- KeyGenerator -----------------------------------------------------------

kg = ActiveSupport::KeyGenerator.new("s3cr3t_key_base")
case_run("kg_sha1_default_64") { kg.generate_key("salt_long_enough").unpack1("H*") }
case_run("kg_sha1_iter1000_32") {
  ActiveSupport::KeyGenerator.new("s3cr3t_key_base", iterations: 1000)
    .generate_key("other salt", 32).unpack1("H*")
}
case_run("kg_sha256_iter65537_16") {
  ActiveSupport::KeyGenerator.new("s3cr3t_key_base", iterations: 65_537,
    hash_digest_class: OpenSSL::Digest::SHA256)
    .generate_key("third salt", 16).unpack1("H*")
}
ckg = ActiveSupport::CachingKeyGenerator.new(
  ActiveSupport::KeyGenerator.new("s3cr3t_key_base"))
case_run("ckg_cache_hit") {
  a = ckg.generate_key("salt_long_enough")
  b = ckg.generate_key("salt_long_enough")
  a == b && a == kg.generate_key("salt_long_enough") ? "same" : "diff"
}

# --- MessageEncryptor: format/wire facts ------------------------------------

case_run("me_key_len") { ActiveSupport::MessageEncryptor.key_len }
case_run("me_default_cipher_parts") {
  # aes-256-gcm AEAD: encrypted--iv--authtag, no extra signature
  crypt = ActiveSupport::MessageEncryptor.new(SECRET, cipher: "aes-256-gcm", serializer: :json)
  crypt.encrypt_and_sign("x").split("--").size
}
case_run("me_iv_part_len") {
  # iv of aes-256-gcm is 12 bytes → strict b64 is 16 chars (parts[1])
  crypt = ActiveSupport::MessageEncryptor.new(SECRET, cipher: "aes-256-gcm", serializer: :json)
  crypt.encrypt_and_sign("x").split("--")[1].size
}
case_run("me_tag_part_len") {
  # auth tag is 16 bytes → strict b64 is 24 chars (parts[2], with padding)
  crypt = ActiveSupport::MessageEncryptor.new(SECRET, cipher: "aes-256-gcm", serializer: :json)
  crypt.encrypt_and_sign("x").split("--")[2].size
}

# --- MessageEncryptor: roundtrips (token + expected decrypt) ----------------

def encryptor(**opts)
  ActiveSupport::MessageEncryptor.new(SECRET,
    **{ cipher: "aes-256-gcm", serializer: :json }.merge(opts))
end

def encrypt_case(id, value, purpose: nil, purpose_read: nil, **opts)
  crypt = encryptor(**opts)
  token = crypt.encrypt_and_sign(value, purpose: purpose)
  puts "#{id}_t\t#{token}"
  puts "#{id}_r\t#{render(crypt.decrypt_and_verify(token, purpose: purpose_read))}"
end

encrypt_case("me_str", "hello world")
encrypt_case("me_unicode", "привет 🌍")
encrypt_case("me_int", 42)
encrypt_case("me_float", 3.14)
encrypt_case("me_nil", nil)
encrypt_case("me_bool", true)
encrypt_case("me_arr", ["a", "b", 3])
encrypt_case("me_hash", { "a" => 1, "b" => ["x", "y"] })
encrypt_case("me_pur", "for login only", purpose: "login", purpose_read: "login")

# wrong purpose / missing purpose → nil (invalid content is caught, not raised)
case_run("me_pur_mismatch") {
  crypt = encryptor
  crypt.decrypt_and_verify(crypt.encrypt_and_sign("v", purpose: "login"), purpose: "shipping")
}
case_run("me_pur_missing") {
  crypt = encryptor
  crypt.decrypt_and_verify(crypt.encrypt_and_sign("v", purpose: "login"))
}
case_run("me_pur_unexpected") {
  crypt = encryptor
  crypt.decrypt_and_verify(crypt.encrypt_and_sign("v"), purpose: "login")
}
case_run("me_expired") {
  crypt = encryptor
  crypt.decrypt_and_verify(crypt.encrypt_and_sign("v", expires_in: -3600))
}
case_run("me_garbage") { encryptor.decrypt_and_verify("not-a-valid-message") }
case_run("me_truncated") {
  encryptor.decrypt_and_verify(encryptor.encrypt_and_sign("some value")[0...-4])
}

# legacy metadata envelope (AS 7.0 / standalone gem format) must decrypt too
encrypt_case("me_legacy", "legacy payload", force_legacy_metadata_serializer: true)
encrypt_case("me_legacy_pur", "legacy purposed", force_legacy_metadata_serializer: true,
             purpose: "cookie.user", purpose_read: "cookie.user")

# url-safe output (no padding, -/_ alphabet)
encrypt_case("me_urlsafe", "url safe value", url_safe: true)
case_run("me_urlsafe_charset") {
  t = encryptor(url_safe: true).encrypt_and_sign("v")
  (t =~ /\A[A-Za-z0-9_\-+=]+\z/) ? "ok" : "bad"
}

# NullSerializer — the credentials.yml.enc wire format (raw bytes in/out)
crypt = ActiveSupport::MessageEncryptor.new(SECRET, cipher: "aes-256-gcm",
  serializer: ActiveSupport::MessageEncryptor::NullSerializer)
raw = "---\nsecret_key_base: abc123\nresend:\n  api_key: 'x'\n"
raw_token = crypt.encrypt_and_sign(raw)
puts "me_null_t\t#{raw_token}"
puts "me_null_r\t#{render(crypt.decrypt_and_verify(raw_token))}"

# MessageVerifier interop (url_safe + purpose — the signed_id / cookies path)
verifier = ActiveSupport::MessageVerifier.new(SECRET, serializer: :json, url_safe: true, digest: "SHA256")
puts "mv_signed_t\t#{verifier.generate("signed payload", purpose: "blob_id")}"
puts "mv_signed_r\t#{render(verifier.verified(signed = verifier.generate("signed payload", purpose: "blob_id"), purpose: "blob_id"))}"
case_run("mv_signed_mismatch") {
  verifier.verified(verifier.generate("signed payload", purpose: "blob_id"), purpose: "other")
}
