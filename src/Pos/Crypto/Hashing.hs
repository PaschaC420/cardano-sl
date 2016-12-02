{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeApplications      #-}

-- | Hashing capabilities.

module Pos.Crypto.Hashing
       ( AbstractHash (..)
       , Hash
       , hashHexF
       , shortHashF
       , hash
       , hashRaw
       , unsafeHash

       , CastHash (castHash)
       ) where

import           Crypto.Hash         (Blake2b_512, Digest, HashAlgorithm,
                                      digestFromByteString)
import qualified Crypto.Hash         as Hash (hash, hashDigestSize, hashlazy)
import           Data.Aeson          (ToJSON (toJSON))
import           Data.Binary         (Binary (..))
import qualified Data.Binary         as Binary
import qualified Data.Binary.Get     as Binary (getByteString)
import qualified Data.Binary.Put     as Binary (putByteString)
import qualified Data.ByteArray      as ByteArray
import           Data.Hashable       (Hashable (hashWithSalt), hashPtrWithSalt)
import           Data.SafeCopy       (SafeCopy (..))
import qualified Data.Text.Buildable as Buildable
import           Formatting          (Format, bprint, fitLeft, later, shown, (%.))
import           System.IO.Unsafe    (unsafePerformIO)
import           Universum

import           Pos.Util            (Raw, getCopyBinary, putCopyBinary)

-- | Hash wrapper with phantom type for more type-safety.
-- Made abstract in order to support different algorithms in
-- different situations
newtype AbstractHash algo a = AbstractHash (Digest algo)
    deriving (Show, Eq, Ord, ByteArray.ByteArrayAccess, Generic, NFData)

-- | Type alias for commonly used hash
type Hash = AbstractHash Blake2b_512

instance Hashable (AbstractHash algo a) where
    hashWithSalt s h = unsafePerformIO $ ByteArray.withByteArray h (\ptr -> hashPtrWithSalt ptr (ByteArray.length h) s)


instance HashAlgorithm algo => SafeCopy (AbstractHash algo a) where
    putCopy = putCopyBinary
    getCopy = getCopyBinary "AbstractHash"

instance HashAlgorithm algo => Binary (AbstractHash algo a) where
    {-# SPECIALIZE instance Binary (Hash a) #-}
    get = do
        bs <- Binary.getByteString $ Hash.hashDigestSize @algo $
              panic "Pos.Crypto.Hashing.get: HashAlgorithm value is evaluated!"
        case digestFromByteString bs of
            -- It's impossible because getByteString will already fail if
            -- there weren't enough bytes available
            Nothing -> panic "Pos.Crypto.Hashing.get: impossible"
            Just x  -> return (AbstractHash x)
    put (AbstractHash h) =
        Binary.putByteString (ByteArray.convert h)

instance Buildable.Buildable (AbstractHash algo a) where
    build (AbstractHash x) = bprint shown x

instance ToJSON (Hash a) where
    toJSON = toJSON . pretty

-- | Short version of 'unsafeHash'.
hash :: Binary a => a -> Hash a
hash = unsafeHash

-- | Raw constructor application.
hashRaw :: ByteString -> Hash Raw
hashRaw = AbstractHash . Hash.hash

-- | Encode thing as 'Binary' data and then wrap into constructor.
unsafeHash :: Binary a => a -> Hash b
unsafeHash = AbstractHash . Hash.hashlazy . Binary.encode

-- | Specialized formatter for 'Hash'.
hashHexF :: Format r (Hash a -> r)
hashHexF = later $ \(AbstractHash x) -> Buildable.build (show x :: Text)

-- | Smart formatter for 'Hash' to show only first @8@ characters of 'Hash'.
shortHashF :: Format r (Hash a -> r)
shortHashF = fitLeft 8 %. hashHexF

-- | Type class for unsafe cast between hashes.
-- You must ensure that types have identical Binary instances.
class CastHash a b where
    castHash :: AbstractHash algo a -> AbstractHash algo b
    castHash (AbstractHash x) = AbstractHash x

instance CastHash a a where
    castHash = identity
