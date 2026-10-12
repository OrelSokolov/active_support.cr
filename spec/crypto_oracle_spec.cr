# Oracle spec: 1:1 mirror of oracle/crypto_cases.rb (KeyGenerator /
# MessageEncryptor). Expected values — oracle/crypto_expected.yml, снятые
# с настоящего activesupport 8.1.4. Пары _t/_r: _t — Ruby-шифротекст,
# который порт расшифровывает и сравнивает с _r. Обратное направление —
# oracle/verify_crypto.rb (порт шифрует → гем расшифровывает).

require "spec"
require "../src/active_support_cr"

SECRET = "0123456789abcdef0123456789abcdef"

def encryptor(**opts)
  ActiveSupport::MessageEncryptor.new(SECRET, **opts)
end

def render(v) : String
  case v
  when JSON::Any
    render(v.raw)
  when Bool, Int32, Int64, Float, String then v.inspect
  when Nil then "nil"
  when Array then "A[#{v.map { |e| render(e) }.join(',')}]"
  when Hash then "H{#{v.to_a.sort_by { |k, _| k.to_s }.map { |k, val| "#{render(k)}=>#{render(val)}" }.join(',')}}"
  when Exception then "raise:#{v.class.name}"
  else v.inspect
  end
end

describe "ActiveSupport crypto oracle (activesupport 8.1.4)" do
  expected = Hash(String, String).new
  File.read_lines(File.join(__DIR__, "..", "oracle", "crypto_expected.yml")).each do |line|
    id, value = line.split('\t', 2)
    expected[id] = value
  end

  it "kg_sha1_default_64" do
    kg = ActiveSupport::KeyGenerator.new("s3cr3t_key_base")
    kg.generate_key("salt_long_enough").hexstring.should eq(
      expected["kg_sha1_default_64"].delete('"'))
  end

  it "kg_sha1_iter1000_32" do
    ActiveSupport::KeyGenerator.new("s3cr3t_key_base", iterations: 1000)
      .generate_key("other salt", 32).hexstring
      .should eq(expected["kg_sha1_iter1000_32"].delete('"'))
  end

  it "kg_sha256_iter65537_16" do
    ActiveSupport::KeyGenerator.new("s3cr3t_key_base", iterations: 65_537,
      digest: :sha256).generate_key("third salt", 16).hexstring
      .should eq(expected["kg_sha256_iter65537_16"].delete('"'))
  end

  it "ckg_cache_hit" do
    ckg = ActiveSupport::CachingKeyGenerator.new(
      ActiveSupport::KeyGenerator.new("s3cr3t_key_base"))
    a = ckg.generate_key("salt_long_enough")
    b = ckg.generate_key("salt_long_enough")
    (a == b).should be_true
    a.should eq(ActiveSupport::KeyGenerator.new("s3cr3t_key_base")
      .generate_key("salt_long_enough"))
  end

  it "me_key_len" do
    ActiveSupport::MessageEncryptor.key_len.should eq(expected["me_key_len"].to_i)
  end

  it "me_default_cipher_parts" do
    encryptor.encrypt_and_sign("x").split("--").size
      .should eq(expected["me_default_cipher_parts"].to_i)
  end

  it "me_iv_part_len" do
    encryptor.encrypt_and_sign("x").split("--")[1].size
      .should eq(expected["me_iv_part_len"].to_i)
  end

  it "me_tag_part_len" do
    encryptor.encrypt_and_sign("x").split("--")[2].size
      .should eq(expected["me_tag_part_len"].to_i)
  end

  # Пары _t/_r: Ruby-шифротекст → порт расшифровывает → сверка с Ruby-результатом.
  # purpose/encryptor-опции для каждого кейса (decrypt должен зеркалить опции
  # шифрования из oracle/crypto_cases.rb#encrypt_case).
  [
    {"me_str", nil, false},
    {"me_unicode", nil, false},
    {"me_int", nil, false},
    {"me_float", nil, false},
    {"me_nil", nil, false},
    {"me_bool", nil, false},
    {"me_arr", nil, false},
    {"me_hash", nil, false},
    {"me_pur", "login", false},
    {"me_legacy", nil, false},
    {"me_legacy_pur", "cookie.user", false},
    {"me_urlsafe", nil, true},
  ].each do |(id, purpose, url_safe)|
    it id do
      crypt = encryptor(url_safe: url_safe)
      value = crypt.decrypt_and_verify(expected["#{id}_t"], purpose: purpose)
      render(value).should eq(expected["#{id}_r"]), "#{id}: got #{value.inspect}"
    end
  end

  it "me_pur_mismatch" do
    token = encryptor.encrypt_and_sign("v", purpose: "login")
    encryptor.decrypt_and_verify(token, purpose: "shipping").should be_nil
  end

  it "me_pur_missing" do
    token = encryptor.encrypt_and_sign("v", purpose: "login")
    encryptor.decrypt_and_verify(token).should be_nil
  end

  it "me_pur_unexpected" do
    token = encryptor.encrypt_and_sign("v")
    encryptor.decrypt_and_verify(token, purpose: "login").should be_nil
  end

  it "me_expired" do
    token = encryptor.encrypt_and_sign("v", expires_in: -1.hours)
    encryptor.decrypt_and_verify(token).should be_nil
  end

  it "me_garbage" do
    expect_raises(ActiveSupport::MessageEncryptor::InvalidMessage) do
      encryptor.decrypt_and_verify("not-a-valid-message")
    end
  end

  it "me_truncated" do
    token = encryptor.encrypt_and_sign("some value")
    expect_raises(ActiveSupport::MessageEncryptor::InvalidMessage) do
      encryptor.decrypt_and_verify(token[0...-4])
    end
  end

  it "me_urlsafe_charset" do
    token = encryptor(url_safe: true).encrypt_and_sign("v")
    token.should match(/\A[A-Za-z0-9_\-+=]+\z/)
  end

  it "me_null (credentials wire format)" do
    crypt = encryptor(serializer: :null)
    raw = "---\nsecret_key_base: abc123\nresend:\n  api_key: 'x'\n"
    token = crypt.encrypt_and_sign(raw)
    # Ruby-шифротекст NullSerializer:
    value = crypt.decrypt_and_verify(expected["me_null_t"])
    value.should eq(expected["me_null_r"].delete('"').gsub("\\n", "\n"))
    # и собственный раундтрип:
    crypt.decrypt_and_verify(token).should eq(raw)
  end

  it "mv_signed (verifier url_safe + purpose)" do
    verifier = ActiveSupport::MessageVerifier.new(SECRET, url_safe: true)
    value = verifier.verified_any(expected["mv_signed_t"], purpose: "blob_id")
    render(value).should eq(expected["mv_signed_r"])
    verifier.verified_any(expected["mv_signed_t"], purpose: "other").should be_nil
  end

  # Реверс: порт шифрует → настоящий гем расшифровывает (oracle/verify_crypto.rb).
  it "reverse roundtrip verified by original gem" do
    reverse_cases = [
      {-> { "reverse string".as(ActiveSupport::MessageEncryptor::MetadataPayload) }, %q("reverse string"), nil},
      {-> { "unicode Юникод 🌍".as(ActiveSupport::MessageEncryptor::MetadataPayload) }, %q("unicode Юникод 🌍"), nil},
      {-> { 42.as(ActiveSupport::MessageEncryptor::MetadataPayload) }, "42", nil},
      {-> { nil.as(ActiveSupport::MessageEncryptor::MetadataPayload) }, "null", nil},
      {-> { (["a", "b"] of String | Symbol).as(ActiveSupport::MessageEncryptor::MetadataPayload) }, %q(["a","b"]), nil},
      {-> { ({"a" => 1, "b" => nil} of String => ActiveSupport::MessageEncryptor::MetadataScalar).as(ActiveSupport::MessageEncryptor::MetadataPayload) }, %q({"a":1,"b":null}), nil},
      {-> { "purposed value".as(ActiveSupport::MessageEncryptor::MetadataPayload) }, %q("purposed value"), "login"},
    ]
    path = File.join(Dir.tempdir, "crails_verify_crypto_#{Random::Secure.hex(8)}.tsv")
    File.write(path, reverse_cases.map do |(mk_value, json, purpose)|
      token = encryptor.encrypt_and_sign(mk_value.call, purpose: purpose)
      "#{json}\t#{purpose || ""}\t#{token}"
    end.join("\n"))
    status = Process.run("ruby",
      [File.join(__DIR__, "..", "oracle", "verify_crypto.rb"), path],
      output: output = IO::Memory.new)
    File.delete(path)
    status.success?.should be_true, "ruby verify_crypto failed:\n#{output}"
    output.to_s.scan(/\tOK/).size.should eq(reverse_cases.size)
  end
end
