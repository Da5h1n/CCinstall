local chacha = require("chacha20") -- The file we downloaded above

local secureAPI = {}
local MASTER_KEY = "my_diamond_vault_123" -- Keep this secret!

-- ENCRYPT AND SEND
function secureAPI.send(id, message)
    -- A 'nonce' is a random number used once to ensure 
    -- the same message looks different every time it's sent.
    local nonce = chacha.generateNonce() 
    local encrypted = chacha.encrypt(message, MASTER_KEY, nonce)
    
    -- Send both the encrypted data and the nonce
    rednet.send(id, {data = encrypted, nonce = nonce}, "SECURE_NET")
end

-- RECEIVE AND DECRYPT
function secureAPI.receive(timeout)
    local sender, packet = rednet.receive("SECURE_NET", timeout)
    
    if packet and packet.data and packet.nonce then
        local decrypted = chacha.decrypt(packet.data, MASTER_KEY, packet.nonce)
        return decrypted, sender
    end
    return nil
end

return secureAPI