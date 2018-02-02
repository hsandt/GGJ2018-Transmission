import json
import os, sys

def load_words():
    filename = os.path.join(os.path.dirname(sys.argv[0]), "words_dictionary.json")
    with open(filename,"r") as english_dictionary:
        valid_words = json.load(english_dictionary)
        return valid_words

def find_permutations(words, permutation_table):
    """
    Return a dictionary of words of length n, associated to their permutation via the permutation table
    if the permutation is also a word in the dictionary (actually any iterable describing the result indices),
    where n is the length of the permutation table.
    UB unless the permutation_table is a sequence of n unique indices between 0 and n-1.
    """
    n = len(permutation_table)
    permutable_words = {}
    # We can either mirror the permutable words (key<-value), or add a set with the values of permutable_words
    # to allow fast access and check if a word is not already among these values during iteration.
    # We choose to mirror.
    for word in words:
        if word in permutable_words:
            continue
        if len(word) != n:
            continue
        characters = [word[i] for i in permutation_table]
        permuted_word = "".join(characters)
        if word == permuted_word:
            # permutation preserves word, just add it once
            permutable_words[word] = word
        elif permuted_word in words:
            permutable_words[word] = permuted_word
            permutable_words[permuted_word] = word
    return permutable_words

if __name__ == '__main__':
    english_words = load_words()
    # permutable_words = find_permutations(english_words, (1, 0, 3, 2))
    # permutable_words = find_permutations(english_words, (0, 2, 1))
    # permutable_words = find_permutations(english_words, (2, 1, 0))
    permutable_words = find_permutations(english_words, (0, 3, 1, 2))
    print(permutable_words)
