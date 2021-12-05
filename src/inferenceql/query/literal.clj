(ns inferenceql.query.literal
  (:refer-clojure :exclude [read])
  (:require [clojure.core.match :as match]
            [clojure.edn :as edn]
            [inferenceql.query.parser.tree :as tree]
            [inferenceql.query.relation :as relation]))

(defn read
  [node]
  (match/match [(into (empty node)
                      (remove tree/whitespace?)
                      node)]
    [[:value child]] (read child)

    [[:bool s]]          (edn/read-string s)
    [[:float s]]         (edn/read-string s)
    [[:int s]]           (edn/read-string s)
    [[:nat s]]           (edn/read-string s)
    [[:simple-symbol s]] (edn/read-string s)
    [[:string s]]        (edn/read-string s)

    [[:null _]] nil
    [nil] nil

    [[:relation-expr child]] (read child)
    [[:value-lists child]] (read child)

    [[:simple-symbol-list & children]]
    (map read (filter tree/branch? children))

    [[:value-lists-full & children]]
    (map read (filter tree/branch? children))

    [[:value-lists-sparse & children]]
    (let [pairs (->> children
                     (filter tree/branch?)
                     (map read)
                     (partition 2))
          n (inc (apply max (map first pairs)))]
      (reduce #(apply assoc %1 %2)
              (vec (repeat n ()))
              pairs))

    [[:value-list & children]]
    (map read (filter tree/branch? children))

    [[:relation-value syms _values vals]]
    (let [attrs (read syms)
          ms (map #(zipmap attrs %)
                  (read vals))]
      (relation/relation ms attrs))))

(comment

 (require '[inferenceql.query.parser :as parser] :reload)

 (-> (parser/parse "... 6: (3), 7: (8) ..." :start :value-lists)
     (tree/only-child-node)
     (tree/child-nodes))

 (read (parser/parse "(3, 4, 5)" :start :value-list))
 (read (parser/parse "... 0: (3), 8: (7) ..." :start :value-lists))
 (read (parser/parse "(x) VALUES ... 10: (3), 20: (4) ..." :start :relation-value))

 ,)