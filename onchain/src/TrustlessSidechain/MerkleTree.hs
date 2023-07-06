{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}

{- | This module is an implementation of a merkle tree suitable for on chain
 and off chain code. This is meant to be imported qualified i.e.,

 > import TrustlessSidechain.MerkleTree qualified as MT

 It is based off of [hydra-poc](https://github.com/input-output-hk/hydra-poc)
 with some improvements.

 Ultimately, the decision to write our own merkle tree came down to:

    1.  We'd like to optimize things later, so it's better if we write our code
    ourselves (so we can actually optimize!)

    2.  There were some low hanging fruit optimizations that we could perform
    already

    3.  We can document ours nicely :)
-}
module TrustlessSidechain.MerkleTree (
  -- * Types
  RootHash (RootHash, unRootHash),
  MerkleProof (MerkleProof, unMerkleProof),
  MerkleTree,

  -- * Building the Merkle Tree
  fromList,
  fromNonEmpty,
  rootHashFromList,

  -- * Creating and querying Merkle proofs / the root hash
  lookupMp,
  lookupsMp,
  lookupsMpFromList,
  memberMp,
  rootMp,
  rootHash,

  -- * Internal
  height,
  mergeRootHashes,
  hash,
  hashLeaf,
  hashInternalNode,
  Side (L, R),
  Up (Up, siblingSide, sibling),

  -- * Internal alternative pretty printers
  pureScriptShowRootHash,
  pureScriptShowUp,
  pureScriptShowMerkleProof,
  pureScriptShowMerkleTree,
) where

import Data.ByteString.Base16 qualified as Base16
import Data.List qualified as List
import Data.String qualified as HaskellString
import GHC.Generics (Generic)
import PlutusPrelude (NonEmpty, on)
import PlutusPrelude qualified
import PlutusTx (makeIsDataIndexed)
import PlutusTx.Builtins qualified as Builtins
import PlutusTx.Builtins.Internal (BuiltinByteString (BuiltinByteString))
import PlutusTx.ErrorCodes qualified
import PlutusTx.Trace qualified as Trace
import Schema qualified
import TrustlessSidechain.HaskellPrelude qualified as TSPrelude
import TrustlessSidechain.PlutusPrelude

{- | 'RootHash' is the hash that is the root of a 'MerkleTree'.

 Internally, this is just a newtype wrapper around 'BuiltinByteString' for
 some type level book keeping to remember what we have hashed and what we
 haven't; and also represents hashes of subtrees of a merkle tree.
-}
newtype RootHash = RootHash {unRootHash :: BuiltinByteString}
  deriving stock (TSPrelude.Show, TSPrelude.Eq, Generic)
  deriving anyclass (Schema.ToSchema)
  deriving newtype (FromData, ToData, UnsafeFromData, TSPrelude.Ord)

-- See #249 for the modified serialisation scheme

-- | 'pureScriptShowRootHash' shows the RootHash in a purescript friendly way.
pureScriptShowRootHash :: RootHash -> HaskellString.String
pureScriptShowRootHash RootHash {unRootHash = rh} =
  List.unwords
    [ "RootHash"
    , "("
    , "hexToByteArrayUnsafe"
    , TSPrelude.show $ case rh of
        BuiltinByteString bs -> Base16.encode bs
    , ")"
    ]

instance Eq RootHash where
  RootHash l == RootHash r = l == r

{- | Internal data type. 'Side' is used in 'Up' to decide whether a *sibling* of a node is on the
 left or right side.

 In a picture,
 >     ...
 >    parent
 >     /  \
 >   you   sibling
 > ...      ...

 >     ...
 >    parent
 >     /  \
 > sibling you
 > ...      ...

 are siblings.

 Note: Serialisation of 'Side'
 ~~~~~~~~~~~~~~~~~~~~~~~~~~~
 See issue #249. We represent
    > L --> Integer 0
    > R --> Integer 1
 instead of doing something like
    > L --> Constructor 0 []
    > R --> Constructor 1 []
 (which would normally generated by the template haskell mechanisms)
-}
data Side = L | R
  deriving stock (TSPrelude.Show, TSPrelude.Eq, Generic)
  deriving anyclass (Schema.ToSchema)

instance ToData Side where
  {-# INLINEABLE toBuiltinData #-}
  toBuiltinData L = toBuiltinData (0 :: Integer)
  toBuiltinData R = toBuiltinData (1 :: Integer)

instance FromData Side where
  {-# INLINEABLE fromBuiltinData #-}
  fromBuiltinData d =
    Builtins.matchData'
      d
      -- To understand this better, I highly recommend looking at the
      -- documentation for 'PlutusTx.Builtins.matchData'' / look at the
      -- generated template haskell code with @-ddump-splices@ with
      -- 'PlutusTx.makeIsDataIndexed'
      (\_ _ -> Nothing) -- constructor case
      (const Nothing) -- map case
      (const Nothing) -- list case
      (\i -> if i == 0 then Just L else if i == 1 then Just R else Nothing) -- integer case
      (const Nothing) -- bytestring case

instance UnsafeFromData Side where
  {-# INLINEABLE unsafeFromBuiltinData #-}
  unsafeFromBuiltinData d =
    let fallthrough = Trace.traceError PlutusTx.ErrorCodes.reconstructCaseError
     in Builtins.matchData'
          d
          (\_ _ -> fallthrough) -- constructor case
          (const fallthrough) -- map case
          (const fallthrough) -- list case
          (\i -> if i == 0 then L else if i == 1 then R else fallthrough) -- integer case
          (const fallthrough) -- bytestring case

{- | Internal data type. 'Up' is a single step up from a leaf of a 'MerkleTree' to recompute the
 root hash. In particular, this data type recovers information of the
 sibling.

 E.g. given the merkle tree,
 >       1234
 >      /    \
 >   12       34
 >  /  \      / \
 >  1   2    3   4
 we will represent the path from @2@ to the root @1234@ by the list
  @[Up L 1, Up R 34]@ -- see 'lookupMp' for more details.
-}
data Up = Up {siblingSide :: Side, sibling :: RootHash}
  deriving stock (TSPrelude.Show, TSPrelude.Eq, Generic)
  deriving anyclass (Schema.ToSchema)

-- | 'pureScriptShowUp' shows Up in a purescript friendly way.
pureScriptShowUp :: Up -> HaskellString.String
pureScriptShowUp (Up ss s) =
  List.unwords
    [ "("
    , "Up"
    , "{"
    , "siblingSide"
    , ":"
    , TSPrelude.show ss
    , ","
    , "sibling"
    , ":"
    , "("
    , pureScriptShowRootHash s
    , ")"
    , "}"
    , ")"
    ]

makeIsDataIndexed ''Up [('Up, 0)]

{- | 'MerkleProof' is the proof to decide whether a 'BuiltinByteString' was
 included in a 'RootHash'.

 See 'memberMp' for details.
-}
newtype MerkleProof = MerkleProof {unMerkleProof :: [Up]}
  deriving stock (TSPrelude.Show, TSPrelude.Eq, Generic)
  deriving anyclass (Schema.ToSchema)
  deriving newtype (FromData, ToData, UnsafeFromData)

-- | 'pureScriptShowMerkleProof' shows the MerkleProof in a purescript friendly way.
pureScriptShowMerkleProof :: MerkleProof -> HaskellString.String
pureScriptShowMerkleProof (MerkleProof proof) =
  List.unwords
    [ "("
    , "MerkleProof"
    , "["
    , List.intercalate "," (map pureScriptShowUp proof)
    , "]"
    , ")"
    ]

-- | 'hash' is an internal function which is a wrapper around the desired hashing function.
{-# INLINEABLE hash #-}
hash :: BuiltinByteString -> RootHash
hash = RootHash . Builtins.blake2b_256

{- | 'hashLeaf' is an internal function used to hash a leaf for the merkle
 tree. See: Note [2nd Preimage Attack on The Merkle Tree]
-}
{-# INLINEABLE hashLeaf #-}
hashLeaf :: BuiltinByteString -> RootHash
hashLeaf = hash . Builtins.consByteString 0

{- | 'hashInternalNode' is an internal function used to hash an internal node
 in the Merkle tree. See: Note [2nd Preimage Attack on The Merkle Tree]
-}
{-# INLINEABLE hashInternalNode #-}
hashInternalNode :: BuiltinByteString -> RootHash
hashInternalNode = hash . Builtins.consByteString 1

-- | 'mergeRootHashes' is an internal function which combines two 'BuiltinByteString' in the 'MerkleTree'
{-# INLINEABLE mergeRootHashes #-}
mergeRootHashes :: RootHash -> RootHash -> RootHash
mergeRootHashes l r = hashInternalNode $ (Builtins.appendByteString `on` unRootHash) l r

{- | 'MerkleTree' is a tree of hashes. See 'fromList' and 'fromNonEmpty' for
 building a 'MerkleTree', and see 'lookupMp' and 'memberMp' for creating and
 verifying 'MerkleProof'.
-}
data MerkleTree
  = Bin RootHash MerkleTree MerkleTree
  | Tip RootHash
  deriving stock (TSPrelude.Show, TSPrelude.Eq)

makeIsDataIndexed ''MerkleTree [('Bin, 0), ('Tip, 1)]

-- | 'pureScriptShowMerkleTree' shows the MerkleTree in a purescript friendly way.
pureScriptShowMerkleTree :: MerkleTree -> HaskellString.String
pureScriptShowMerkleTree = \case
  Bin rh l r ->
    List.unwords
      [ "Bin"
      , "("
      , pureScriptShowRootHash rh
      , ")"
      , "("
      , pureScriptShowMerkleTree l
      , ")"
      , "("
      , pureScriptShowMerkleTree r
      , ")"
      ]
  Tip rh ->
    List.unwords
      [ "Tip"
      , "("
      , pureScriptShowRootHash rh
      , ")"
      ]

-- Note [Merkle Tree Invariants]:
--      1. @Bin h l r@ satisfies @h = rootHash l `mergeRootHashes` rootHash r@

-- | 'height' is used for QuickCheck to verify invariants.
{-# INLINEABLE height #-}
height :: MerkleTree -> Integer
height = \case
  Bin _ l r -> 1 + max (height l) (height r)
  Tip _ -> 1

-- | /O(1)/ 'rootHash' returns the topmost hash.
{-# INLINEABLE rootHash #-}
rootHash :: MerkleTree -> RootHash
rootHash = \case
  Bin h _ _ -> h
  Tip h -> h

{- | @'rootHashFromList' = 'rootHash' . 'fromList'@ i.e., 'rootHashFromList'
 computes the merkle tree and returns the root. As in 'fromList', this throws
 an exception in the case the input list is empty.
-}
{-# INLINEABLE rootHashFromList #-}
rootHashFromList :: [BuiltinByteString] -> RootHash
rootHashFromList = rootHash . fromList

{- | /O(n)/.
 Throws an error when the list is empty, but otherwise is 'fromNonEmpty'.

 > 'fromList' [] == error
 > fromList ["a", "b"] == fromNonEmpty ["a", "b"]
-}
{-# INLINEABLE fromList #-}
fromList :: [BuiltinByteString] -> MerkleTree
fromList [] = traceError "illegal TrustlessSidechain.MerkleTree.fromList with empty list"
fromList lst = mergeAll . map (Tip . hashLeaf) $ lst
  where
    -- Note [Number of Nodes in the MerkleTree / Run Time]
    -- The number of nodes (Bin / Tip constructors) is in /O(n)/ where
    -- /n/ is the size of the original list. Observe that we can count the number
    -- of nodes created via the recurrence
    -- > T(n) = T(n/2) + n
    -- and a straightforward application of case 3 of the master theorem gives
    -- us that this is /O(n)/ as it's easy to choose /\epsilon > 0/ s.t.
    -- /n \in \Omega(n^(\log_2 1 + \epsilon)) = \Omega(n^(\epsilon))/.
    -- The run time is analyzed similarly.
    --
    -- Note [Tail Recursive mergePairs]
    -- Previously, the recursive step of @mergePairs :: [MerkleTree] ->
    -- [MerkleTree]@ was written as
    -- > mergePairs (a : b : cs) =
    -- >   let a' = rootHash a
    -- >       b' = rootHash b
    -- >    in Bin (mergeRootHashes a' b') a b : mergePairs cs
    -- but this causes problems in non-lazy functional languages since
    -- mergePairs does not occur in the tail position, and hence this
    -- accumulates stack space.
    mergeAll :: [MerkleTree] -> MerkleTree
    mergeAll [r] = r
    mergeAll rs = mergeAll $ mergePairs [] rs

    mergePairs :: [MerkleTree] -> [MerkleTree] -> [MerkleTree]
    mergePairs acc (a : b : cs) =
      let a' = rootHash a
          b' = rootHash b
       in mergePairs (Bin (mergeRootHashes a' b') a b : acc) cs
    mergePairs acc [a] = a : acc
    mergePairs acc [] = acc

{- | /O(n)/. Builds a 'MerkleTree' from a 'NonEmpty' list of
 'BuiltinByteString'.

 An example of using 'fromNonEmpty':

 > {\-# LANGUAGE OverloadedStrings #-\}
 > import TrustlessSidechain.MerkleTree qualified as MT
 > import PlutusPrelude qualified
 > pubkey1, pubkey2 :: BuiltinByteString
 > pubkey1 = "pubkey1"
 > pubkey2 = "pubkey2"
 > merkleTree = MT.fromNonEmpty $ PlutusPrelude.fromList [ pubkey1, pubkey2 ]

 Pictorially, given @["p1", "p2", "p3"]@, this creates a tree like
 >    hash (1 : hash (1 : hash (0:"p1") ++ hash (0:"p2")) ++ hash (0:"p3"))
 >              /                               |
 >    hash (1 : hash (0:"p1") ++ hash (0:"p2")) |
 >      /                    \                  |
 > hash (0:"p1")          hash (0:"p2")       hash (0:"p3")

 N.B. observe how all the leaves are prepended with @0@ before being hashed,
 and all the internal nodes are prepended by @1@ before being hashed. For more
 details, see Note [2nd Preimage Attack on The Merkle Tree].

 N.B. it doesn't follow exactly this anymore -- as it builds the tree up, each
 layer is reversed to make constructing the tree tail recursive. See Note [Tail
 Recursive mergePairs]
-}
{-# INLINEABLE fromNonEmpty #-}
fromNonEmpty :: NonEmpty BuiltinByteString -> MerkleTree
fromNonEmpty = fromList . PlutusPrelude.toList

{-
Properties [Merkle Tree Height Bound]
    Let lst be an arbitrary non empty list.
        height (fromNonEmpty lst) <= floor(log_2 (length lst)) + 2

See: Note [Hydra-Poc People Merkle Tree Comparisons]
-}

{- | /O(n)/ where /n/ is the size of the list used to make the merkle
 tree.

 Lookup the the corresponding merkle proof of the 'BuiltinByteString' in the
 'MerkleTree' i.e., this builds the merkle proof for the given
 'BuiltinByteString' corresponding to this 'MerkleTree' if such a merkle proof
 exists.

 The function will return the corresponding proof as @('Just' value)@, or
 'Nothing' if the Merkle tree does not contain the hash of the
 'BuiltinByteString'

 An example of using 'lookupMp':

 > {\-# LANGUAGE OverloadedStrings #-\}
 > import Data.Maybe (isJust)
 > import TrustlessSidechain.MerkleTree qualified as MT
 >
 > dogs = MT.fromList [ "maltese", "pomeranian", "yorkie" ]
 >
 > main = do
 >     print $ isJust $ lookupMp "maltese" dogs
 >     print $ isJust $ lookupMp "golden retriever" dogs

 The output of this program:

 >   True
 >   False
-}
{-# INLINEABLE lookupMp #-}
lookupMp :: BuiltinByteString -> MerkleTree -> Maybe MerkleProof
lookupMp bt mt = fmap MerkleProof $ go [] mt
  where
    -- Note: this is implemented by doing a dfs through the tree and hence the
    -- linear running time, since by Note [Number of Nodes in the MerkleTree /
    -- Run Time] we know that there are a linear number of nodes.
    hsh :: RootHash
    hsh = hashLeaf bt

    go :: [Up] -> MerkleTree -> Maybe [Up]
    go prf = \case
      -- Note [lookupMp Invariants].
      --
      --  1. @Left l@ means @l@ is on the *left* side so @hsh@ was on the
      --  *right* side
      --
      --  2. @Right r@ means @r@ is on the *right* side so @hsh@ was on the
      --  *left* side
      --
      -- Note that we implicitly "reverse" the list so that the deepest node
      -- in the 'MerkleTree' is at the head of the list.
      Bin _h l r ->
        let l' = rootHash l
            r' = rootHash r
         in go (Up L l' : prf) r PlutusPrelude.<|> go (Up R r' : prf) l
      Tip h
        | hsh == h -> Just prf
        | otherwise -> Nothing

{- Properties.
    1. Suppose lst is an arbitrary non empty list.
            x \in lst <==> isJust (lookupMp x (fromNonEmpty lst))

    2.
        Just prf = lookupMp x (fromNonEmpty lst) ==> length prf <= floor (log_2 (length lst)) + 1

    N.B. 2. follows from [Merkle Tree Height Bound].
-}

{- | @/O(n log n)/@ where /n/ is the size of the list used to make the merkle
 tree.

 'lookupsMp' mt@ returns all leafs associated with its 'MerkleProof' in a list
 (the order of the list output is unspecified and may be a bit surprising due
 to Note [Tail Recursive mergePairs]). This is useful for making an efficient
 mapping of the elements in the merkle tree to its corresponding merkle proof
 since alternatively one would have to do repeated /n/ calls to 'lookupMp'
 (which is O(/n/) being /O(n^2)/ altogether.

 Example.
 Given
 > dogs = MT.fromList [ "pomeranian", "yorkie" ]
 we have that @lookupsMp dogs@ (although the order of the list is
 unspecified) is
 > [ (hashLeaf "pomeranian", mp1), (hashLeaf "yorkie", mp2) ]
 where @Just mp1 = lookupMp "pomeranian" dogs@ and @Just mp2 = lookupMp "yorkie" dogs@.
-}
lookupsMp :: MerkleTree -> [(RootHash, MerkleProof)]
lookupsMp = ($ []) . go []
  where
    -- Similarly to 'lookupMp', this does a dfs through the tree to gather the
    -- paths, and is implemented via a difference list for efficient
    -- concatenation.
    --
    -- Complexity analysis.
    -- - Recursing through the entire tree is bounded by /O(n)/
    -- - Difference list appending is /O(1)/ (and /O(n)/ at the end)
    -- - There are /n/ merkle proofs, and each are of length /O(log n)/
    -- Hence, we have /O(n log n)/ complexity (when evaluating to a normal form).
    go :: [Up] -> MerkleTree -> [(RootHash, MerkleProof)] -> [(RootHash, MerkleProof)]
    go prf mt = case mt of
      -- See Note [lookupMp Invariants] for the invariants here.
      Bin _h l r ->
        let l' = rootHash l
            r' = rootHash r
         in go (Up L l' : prf) r . go (Up R r' : prf) l
      Tip h -> ((h, MerkleProof prf) :)

{-
 Properties.
    1. Suppose lst is an arbitrary non empty list of distinct elements.
            (roothash, merkleProof) \in lookupsMp (fromNonEmpty lst)
                ===> there exists x \in lst s.t.
                    Just merkleProof' (lookupMp x (fromNonEmpty lst)),
                    merkleProof == merkleProof',
                    rootHash = hashLeaf x

            x \in lst,  Just merkleProof = (lookupMp x (fromNonEmpty lst))
                ===> (hash x, merkleProof) \in  lookupsMp (fromNonEmpty lst)
    2. Suppose lst is an arbitrary non empty list of length n.
        length (lookupsMp (fromNonEmpty lst)) == n
-}

{- | @'lookupsMpFromList'@ is essentially @'lookupsMp' . 'fromList'@, but also
 returns the entire merkletree in the first projection of the tuple.
-}
lookupsMpFromList :: [BuiltinByteString] -> (MerkleTree, [(RootHash, MerkleProof)])
lookupsMpFromList inputs =
  let merkleTree = fromList inputs
   in (merkleTree, lookupsMp merkleTree)

{- | /O(n)/ in the length of the 'MerkleProof' (which is /O(log n)/ of
 the size of the original list to create the 'MerkleTree' of the given
 'RootHash').

 An example of using 'memberMp':

 > let merkleTree = fromList ["maltese", "pomeranian", "yorkie"]
 > let Just prf = lookupMp "maltese" merkleTree
 > memberMp "maltese" prf (rootHash merkleTree) == True
-}
{-# INLINEABLE memberMp #-}
memberMp :: BuiltinByteString -> MerkleProof -> RootHash -> Bool
memberMp bt prf rth = rth == rootMp bt prf

{- | @'rootMp' bt prf@ computes the root of a merkle tree with @bt@ as the
 missing element, and @prf@ is the proof of @str@ being in the merkle tree.
-}
rootMp :: BuiltinByteString -> MerkleProof -> RootHash
rootMp bt prf = go (hashLeaf bt) (unMerkleProof prf)
  where
    -- This just undoes the process given in 'lookupMp'.
    go :: RootHash -> [Up] -> RootHash
    go acc [] = acc
    go acc (p : ps) = case siblingSide p of
      L -> go (mergeRootHashes (sibling p) acc) ps
      R -> go (mergeRootHashes acc (sibling p)) ps

{- Properties.
    Suppose lst is an arbitrary non empty list.
    Let tree = fromNonEmpty lst
        Just prf = lookupMp x tree <==> memberMp x prf (rootHash tree) = True
-}

{-
 Note [2nd Preimage Attack on The Merkle Tree]

 A previous implementation was susceptible to a 2nd Preimage Attack. Let's
 recall how the Merkle root was constructed previously. Given a nonempty list of /leaves/,
 we computed the Merkle root by

    1. Hashing all the leaves

    2. Linearly scan through the leaves and replace adjacent leaves with the
    hash of the two leaves appended together

    3. Repeat 2. until we are left with one hash.

 For example, given the non empty list @[a,b,c,d]@, we would compute the Merkle
 root as follows (where @h@ denotes the hash function and @++@ denotes append):

 >     h(h(h(a)++h(b))++h(h(c)++h(d)))
 >         /                   \
 >  h(h(a)++h(b))        h(h(c)++h(d))
 >   /        \           /          \
 > h(a)      h(b)       h(c)        h(d)

 Now, it's easy to see that an adversary can give a distinct nonempty list which would
 form the same Merkle root (which in our example is
 @h(h(h(a)++h(b))++h(h(c)++h(d)))@).
 Consider the non empty list @[h(a)++h(b), h(c)++h(d)]@, and we observe that the Merkle root is computed like

 > h(h(h(a)++h(b))++h(h(c)++h(d)))
 >     /                   \
 > h(h(a)++h(b))        h(h(c)++h(d))

 which has the same root as our original Merkle tree.

 From this result, it is easy to see how one can generate data and proofs for a
 Merkle tree which weren't originally in the Merkle tree.

 To fix this, it's quite simple. We change the procedure to

    1. Prepend a 0 byte to all the leaves, then hash all the leaves individually

    2. Linearly scan through the leaves and replace adjacent leaves with the
    hash of the two leaves appended together prepended with a 1 byte i.e., two
    adjacent leaves @leaf0@ and @leaf1@ is replaced by the single leaf @hash(1
    ++ leaf0 ++ leaf1)@

    3. Repeat 2. until we are left with one hash.

 As an example, given the nonempty list @[a,b,c,d]@, we would compute the Merkle root as

 >       h(1++h(1++h(0++a)++h(0++b))++h(1++h(0++c)++h(0++d)))
 >             /                                    \
 >  h(1++h(0++a)++h(0++b))                  h(1++h(0++c)++h(0++d))
 >   /        \                                 /          \
 > h(0++a)      h(0++b)                     h(0++c)        h(0++d)

 Why does this fix this? If we assume that the underlying hash function @h@ is
 collision resistant, this essentially implies that the @h@ is injective. This
 means that an adverary MUST choose the preimage of one the horizontal "levels"
 as the nonempty list without the @0@ or @1@ prepended. So, if the adversary
 chose any of the levels, the algorithm would prepend a @0@ to it, which would
 mean the root would be different if the adversary picked anything but the
 original leafs i.e., this is collision resistant.
-}

{-
Note [Hydra-Poc People Merkle Tree Comparisons]

We discuss some comparisions between us and the hydra-poc people.

We first note that the hydra-poc people's implementation is susceptible to a
2nd preimage attack whereas ours isn't -- see: Note [2nd Preimage Attack on The
Merkle Tree]

The second main difference how the merkle tree is actually constructed, and we
spend the remaining of this note discussing this aspect. They do a top down
approach (compute the length of the list, divide by 2, then split the list into
the first half / second half, then keep going), where as we do a "bottom up"
approach.

N.B. This technique of going "bottom up" to create the tree is well known
when implementing merge sort
    [1] See 'Data.List.sort'
    [2] "When You Should Use Lists In Haskell (Mostly You Should Not)" by Johannes Waldmann
    [3] "Algorithm Design in Haskell" by Richard Bird / Jeremy Gibbons

The hydra-poc people claim their tree has an exact height upper bound as given
in [Merkle Tree Height Bound]. It's a bit of a peculier choice of constants
[this is implied in their QuickCheck tests], but if we want our implementation
to be at least as good as their solution, we should show that our trees are
bound by the same bound.

We sketch out why this is the case.

Observation 1.
    The height of a merkle tree is upper bounded by the recurrence

    T(n) = 1                    if n = 1
           T(ceil(n/2)) + 1     otherwise

    since this counts the number of times the mergePairs function gets called
    in 'fromList' where we may observe that the height of the tree increases by
    one iff mergePairs gets called.

Thus, it suffices to show

    T(n) <= floor(log_2(n)) + 2

for every n >= 1.

Claim 1.
    for every k >= 0
    T(2^k) = log_2(n) + 1

Proof.
    By induction on k.

Claim 2.

    T(n) <= floor(log_2(n)) + 2

for every n >= 1.

Proof. By Claim 1. we only need to consider the case when n is not a power of
2. In which case we may write
    2^k < n
where k is the largest integer satisfying this inequality.
It follows that
    2^k / 2 < ceil(n/2) <= 2^k < n          (*)
and observing that the recurrence T is obviously increasing, we get that
    T(n) = T(ceil(n/2)) + 1
         <= T(2^k) + 1          [T is increasing]
         = (log_2 2^k + 1) + 1  [Claim 1]
         = log_2 2^k + 2
         <= floor(log_2 n) + 2          [Apply (*)]
as required.
-}
